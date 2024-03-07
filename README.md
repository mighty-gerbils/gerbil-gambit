# Gerbil as Gambit modules

This repo provides support for using Gerbil runtime modules as gambit modules,
so that they can be integrated in pure gambit programs.

## Build and Usage

First, you need to [install Gerbil](https://cons.io/guide/) in your system.

Then just run the `build.ss` script:
```
./build.ss
```

This will build the necessary gambit module structure in `modules`.

To use, just pass `-:search=path/to/gerbil-gambit/modules` to gsi/gsc.

## Limitations
- only the runtime code is present, no macros; that's hard to fix,
  but we'll get to it eventually.
- stdlib external foreign deps don't work yet; that should be easy to fix
  by fishing the necessary cc and ld options from the stdlib build-spec.


**Note** I have only tested this on Linux. MacOS build might be a bit of a
problem with the foreign external dependencies; we normally build
Gerbil for the Mac with homebrew and a Mac expert user should help
with this.

## Demo

Here is a small example [script](demo.scm) that uses `getopt` to parse arguments:
```
$ cat demo.scm
#!/usr/bin/env gsi

(import (std cli getopt))

(define (main . args)
  (call-with-getopt demo-main args
                    program: "demo"
                    help: "a small demo script"
                    (command "hello" help: "say hello")
                    (command "goodbye" help: "say goodbye")))

(define (demo-main cmd opt)
  (case cmd
    ((hello) (display "hello, ") (display (getenv "USER")) (newline))
    ((hello) (display "goodbye, ") (display (getenv "USER")) (newline))))

$ ./demo.scm hello
hello, vyzo
$ ./demo.scm goodbye
goodbye, vyzo
```
