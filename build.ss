(import :gerbil/expander
        :gerbil/compiler
        :std/iter
        :std/srfi/1)

(def static-dir (path-expand "lib/static" (gerbil-home)))

(def (main (output-path (path-expand "modules" (current-directory))))
  (create-directory* output-path)
  (for (f (directory-files static-dir))
    (when (or (string-prefix? "gerbil__runtime" f)
              (string-prefix? "std__")))
      (generate-module f output-path)))

(def (generate-module f output-path)
  (let* ((modf    (path-string-extension f))
         (modpath (string-split modf #\_))
         (modpath (filter (? (not string-empty?)) modpath))
         (modname (string-join modpath #\/))
         (moddir  (path-expand modname output-path))
         (libpath (map string->symbol modpath))
         (libid   (string->symbol modname))
         (ctx     (import-module libid))
         (ns      (or (module-context-ns ctx) ""))
         (libin   (module-runtime-imports ctx))
         (libout  (module-runtime-exports ctx))
         (libname (last modpath))
         (lib.sld (path-expand (string-append libname ".sld") moddir)))
    (create-directory* moddir)
    (copy-file (path-expand f static-dir) moddir)
    (call-with-output-file lib.sld
      (lambda (output-sld)
        (pretty-print
         `(define-library ,libpath
            (namespace ,ns)
            (import ,@libin)
            (export ,@libout)
            (include ,f))
         output-sld)))))

(def (module-runtime-imports ctx)
  (map (lambda (id)
         (map string->symbol
              (string-split
               (symbol->string id)
               #\/)))
       (gxc#find-runtime-module-deps ctx)))

(def (module-runtime-exports ctx)
  (filter-map
   (lambda (xport)
     (if (and (module-export? xport)
              (fxzero? (module-export-phi xport)))
       (if (eq? (module-export-key xport)
                (module-export-name xport))
         (module-export-name)
         [(module-export-key xport) (module-export-name xport)])))
   (module-context-exports ctx)))
