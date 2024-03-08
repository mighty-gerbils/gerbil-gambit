#!/usr/bin/env gxi

(import :gerbil/expander
        :std/sugar
        :std/iter
        :std/srfi/1
        :std/srfi/13
        :std/pregexp
        :std/misc/process)

(def static-dir (path-expand "lib/static" (gerbil-home)))
(def libraries (make-hash-table))
(def references (make-hash-table))
(def only-dep-references
  (hash
   ((std actor-v18 message) #t)
   ((std net websocket interface) #t)))

(def compilation-flags
  (hash
   ((std text _zlib) ["-ld-options" "-lz"])
   ((std net libssl)
    (cond-expand
      (darwin ["-ld-options" "-lssl -lcrypto -lgambit"])
      (else ["-ld-options" "-lssl"])))
   ((std crypto libcrypto)
    ["-cc-options" "-Wno-deprecated-declarations -Wno-implicit-function-declaration"
     "-ld-options" "-lcrypto"])
   ((std db _sqlite)
    ["-ld-options" "-lsqlite3 -lm" ])))

(def (main (output-path (path-expand "modules" (current-directory)))
           (gsc "gsc"))
  (create-directory* output-path)
  ;; first we need this
  (generate-gambit-macros-module! output-path)
  ;; and then we can generate the modules
  (for (f (directory-files static-dir))
    (when (and (or (string-prefix? "gerbil__runtime" f)
                   (string-prefix? "std__" f))
               (not (string-contains f "$")))
      (generate-module f output-path)))
  ;; generate empty stubs for missing references
  (generate-stubs! output-path)
  ;; compile the modules
  (compile-libraries! output-path gsc))

(def (generate-gambit-macros-module! output-path)
  (displayln "... generate (gambit-macros)")
  (def define-macro-rx (pregexp "[(]define-macro [(](macro-[A-Za-z0-9!?-]+)"))
  (def use-macro-rx (pregexp "[(](macro-[A-Za-z0-9!?-]+)"))
  (def referenced-macros (make-hash-table-eq))
  (for (f (directory-files static-dir))
    (call-with-input-file (path-expand f static-dir)
      (lambda (input)
        (def local-definitions (make-hash-table-eq))
        (def local-references (make-hash-table-eq))
        (for (line (in-input-lines input))
          (cond
           ((pregexp-match define-macro-rx line)
            => (lambda (m)
                 (hash-put! local-definitions (string->symbol (cadr m)) #t)))
           ((pregexp-match use-macro-rx line)
            => (lambda (m)
                 (hash-put! local-references (string->symbol (cadr m)) #t)))))
        (for (ref (hash-keys local-references))
          (unless (hash-get local-definitions ref)
            (hash-put! referenced-macros ref #t))))))
  (let (gambit-macros.sld (path-expand "gambit-macros.sld" output-path))
    (call-with-output-file gambit-macros.sld
      (lambda (output-file)
        (pretty-print
         `(define-library (gambit-macros)
            (namespace "")
            (export ,@(hash-keys referenced-macros)))
         output-file)))))

(def (generate-stubs! output-path)
  (for (ref (hash-keys references))
    (let* ((libpath (path-expand (string-join (map symbol->string ref) "/") output-path))
           (sld-file (string-append libpath ".sld"))
           (libpath-sld-file (path-expand (string-append (symbol->string (last ref)) ".sld") libpath)))
      (unless (or (file-exists? sld-file)
                  (file-exists? libpath-sld-file))
        (displayln "... fixup " ref)
        (create-directory* (path-directory sld-file))
        (call-with-output-file sld-file
          (lambda (output-sld)
            (display `(define-library ,ref) output-sld)))))))

(def (generate-module f output-path)
  (let* ((modf    (path-strip-extension f))
         (modpath (pregexp-split "__" modf))
         ;;(modpath (filter (? (not string-empty?)) modpath))
         (modname (string-join modpath "/"))
         (moddir  (path-expand modname output-path))
         (libpath (map string->symbol modpath))
         (modid   (string->symbol (string-append ":" modname)))
         (ctx     (import-module modid))
         (ns      (cond
                   ((module-context-ns ctx) => (cut string-append <> "#"))
                   (else "")))
         (libin   (module-runtime-imports ctx))
         (libin-filtered
          (map (lambda (dep)
                 (match dep
                   (['std 'srfi . _] ['only dep])
                   (else
                    (if (hash-get only-dep-references dep)
                      ['only dep]
                      dep))))
               libin))
         (libout  (module-runtime-exports ctx))
         (libname (last modpath))
         (libid   (string->symbol modname))
         (lib.sld (path-expand (string-append libname ".sld") moddir))
         (lib.scm (path-expand (string-append libname ".scm") moddir)))
    (displayln "... generate " libpath)
    (create-directory* moddir)
    (copy-file (path-expand f static-dir) (path-expand f moddir))
    (call-with-output-file lib.sld
      (lambda (output-sld)
        (pretty-print
         `(define-library ,libpath
            (namespace ,ns)
            (import (gambit))
            (import (gambit-macros))
            ,@(if (not (eq? (car libpath) 'gerbil))
                ;; get the properly (un)namespaced runtime symbols
                '((import (gerbil runtime)))
                '())
            (import ,@libin-filtered)
            (export ,@libout)
            (include ,(path-strip-directory lib.scm)))
         output-sld)))
    (call-with-output-file lib.scm
      (lambda (output-scm)
        ;; this is useful for segfault debugging
        ;; (write `(display '(load ,libid)) output-scm)
        ;; (write '(newline) output-scm)
        ;; (newline output-scm)

        (write `(##supply-module ,libid) output-scm)
        (newline output-scm)
        (unless (eq? 'gerbil (car libpath))
          (write '(##demand-module gerbil/runtime) output-scm)
          (newline output-scm))
        (for (dep libin)
          (write `(##demand-module ,(string->symbol (string-join (map symbol->string dep) "/"))) output-scm)
          (newline output-scm))
        (write `(##include ,f) output-scm)
        (newline output-scm)))
    ;; track the module and it's deps
    (hash-put! libraries libpath libin)
    ;; track deps for the "empty file is not generated" issue
    (for-each (cut hash-put! references <> #t) libin)))

(def (module-runtime-imports ctx)
  (filter-map
   (lambda (dep-id)
     (let (dep-str (symbol->string dep-id))
       (and (not (string-prefix? "gerbil/core" dep-str))
            (map string->symbol (string-split dep-str  #\/)))))
   (module-runtime-import-ids ctx)))

(def (module-runtime-import-ids ctx)
  (reverse
   (map expander-context-id
        (delete-duplicates!
         (filter-map
          (lambda (in)
            (let recur ((in in))
              (cond
               ((module-context? in) in)
               ((module-import? in)
                (and (fxzero? (module-import-phi in))
                     (recur (module-export-context (module-import-source in)))))
               ((import-set? in)
                (and (fxzero? (import-set-phi in))
                     (import-set-source in)))
               (else #f))))
          (module-context-import ctx))))))

(def (module-runtime-exports ctx)
  (delete-duplicates!
   (filter-map
    (lambda (xport)
      (and (module-export? xport)
           (fxzero? (module-export-phi xport))
           (let (b (core-resolve-module-export xport))
             (and (not (extern-binding? b)) ; no import, so they will get name clobbered
                  (not (expander-binding? b)) ; no macros
                  (if (eq? (module-export-key xport)
                           (module-export-name xport))
                    (module-export-name xport)
                    `(rename ,(module-export-key xport) ,(module-export-name xport)))))))
    (module-context-export ctx))))

(def (compile-libraries! output-path gsc)
  (def search-path (string-append "-:search=" output-path))
  (def compiled (make-hash-table))
  (def (compile! library)
    (unless (hash-get compiled library)
      (let (sld-path (path-expand (string-append (symbol->string (last library)) ".sld")
                                  (path-expand (string-join (map symbol->string library) "/") output-path)))
        (when (file-exists? sld-path)
          (displayln "... compile " sld-path)
          (let (flags (hash-ref compilation-flags library []))
            (invoke gsc [search-path ;; "-debug-source" "-track-scheme"
                                     flags ...
                                     "-e" "(include \"~~lib/_gambit#.scm\")"
                                     sld-path]))
          (hash-put! compiled library #t)))))
  (for ((values library deps) (in-hash libraries))
    (displayln "... compiling " library)
    (for (dep deps)
      (compile! dep))
    (compile! library)))
