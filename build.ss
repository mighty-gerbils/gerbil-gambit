#!/usr/bin/env gxi

(import :gerbil/expander
        :gerbil/compiler
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
  (for (f (directory-files static-dir))
    (when (and (or (string-prefix? "gerbil__runtime" f)
                   (string-prefix? "std__" f))
               (not (string-contains f "$")))
      (generate-module f output-path)))
  ;; generate empty stubs for missing references
  (generate-stubs! output-path)
  ;; compile the modules
  (compile-libraries! output-path gsc))

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
            ,@(if (not (eq? (car libpath) 'gerbil))
                '((import (only (gerbil runtime))))
                '())
            (import ,@libin-filtered)
            (export ,@libout)
            (include ,lib.scm))
         output-sld)))
    (call-with-output-file lib.scm
      (lambda (output-scm)
        (write `(##supply-module ,libid) output-scm)
        (newline output-scm)
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
  (map (lambda (dep)
         (map string->symbol
              (string-split
               (symbol->string
                (expander-context-id dep))
               #\/)))
       (filter
        (lambda (dep)
          (not (string-prefix? "gerbil/core" (symbol->string (expander-context-id dep)))))
        (gxc#find-runtime-module-deps ctx))))

(def (module-runtime-exports ctx)
  (delete-duplicates!
   (filter-map
    (lambda (xport)
      (and (module-export? xport)
           (fxzero? (module-export-phi xport))
           (let (b (core-resolve-module-export xport))
             (and (not (import-binding? xport))
                  (not (extern-binding? xport))
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
            (invoke gsc [search-path flags ...
                                     "-e" "(include \"~~lib/_gambit#.scm\")"
                                     sld-path]))
          (hash-put! compiled library #t)))))
  (for ((values library deps) (in-hash libraries))
    (displayln "... compiling " library)
    (for (dep deps)
      (compile! dep))
    (compile! library)))
