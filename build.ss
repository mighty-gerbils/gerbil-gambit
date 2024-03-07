#!/usr/bin/env gxi

(import :gerbil/expander
        :gerbil/compiler
        :std/iter
        :std/srfi/1
        :std/srfi/13
        :std/pregexp)

(def static-dir (path-expand "lib/static" (gerbil-home)))
(def references (make-hash-table))

(def (main (output-path (path-expand "modules" (current-directory))))
  (create-directory* output-path)
  (for (f (directory-files static-dir))
    (when (and (or (string-prefix? "gerbil__runtime" f)
                   (string-prefix? "std__" f))
               (not (string-contains f "$")))
      (generate-module f output-path)))
  ;; generate empty stubs for missing references
  (for (ref (hash-keys references))
    (let (libpath (path-expand (string-join (map symbol->string ref) "/") output-path))
      (unless (file-exists? libpath)
        (displayln "... fixup " ref)
        (let (sld-file (string-append libpath ".sld"))
          (create-directory* (path-directory sld-file))
          (call-with-output-file sld-file
            (lambda (output-sld)
              (display `(define-library ,ref) output-sld))))))))

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
         (libout  (module-runtime-exports ctx))
         (libname (last modpath))
         (lib.sld (path-expand (string-append libname ".sld") moddir)))
    (displayln "... generate " libpath)
    (create-directory* moddir)
    (copy-file (path-expand f static-dir) (path-expand f moddir))
    (call-with-output-file lib.sld
      (lambda (output-sld)
        (pretty-print
         `(define-library ,libpath
            (namespace ,ns)
            ,@(if (not (eq? (car libpath) 'gerbil))
                '((import (gerbil runtime)))
                '())
            (import ,@libin)
            (export ,@libout)
            (include ,f))
         output-sld)))
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
