#!/usr/bin/env gsi

(import (std cli getopt))

(define (main . args)
  (call-with-getopt demo-main args
                    program: "demo"
                    help: "a small demo script"
                    (command 'hello help: "say hello")
                    (command 'goodbye help: "say goodbye")))

(define (demo-main cmd opt)
  (case cmd
    ((hello) (display "hello, ") (display (getenv "USER")) (newline))
    ((hello) (display "goodbye, ") (display (getenv "USER")) (newline))))
