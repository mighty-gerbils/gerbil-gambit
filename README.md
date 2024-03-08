# Gerbil as Gambit modules

This repo provides support for using Gerbil runtime modules as gambit modules,
so that they can be integrated in pure gambit programs.

## Build and Usage

First, you need to [install Gerbil](https://cons.io/guide/) in your system.
Please use master, after some required [fixes](https://github.com/mighty-gerbils/gerbil/pull/1153). Your Gambit should also be master, as Marc a blocking issue with the [module cache](https://github.com/gambit/gambit/commit/60ad373b8cfe1338ab8fb3e00d19100c8d76ee41).

Then just run the `build.ss` script:
```
./build.ss
```

This will generate and compile the gerbil and std module structure in `modules`.

To use, just pass `-:search=path/to/gerbil-gambit/modules` to gsi/gsc.

## Limitations

There are a few limitations:
- only the runtime code is present, no macros; that's hard to fix,
  but we'll get to it eventually.
- the built modules do not include the expander or compiler; things that
  depend on them (macros or tools mostly) just won't work.
- reexports are not emitted for wrapper modules. The problem here is that
  the .sld model with the namespace declaration just breaks reexport namespacing
  completely. So you have to import deep and can't rely on package facades.

**Note** I have only tested this on Linux; your mileage may vary in other systems.

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
    ((goodbye) (display "goodbye, ") (display (getenv "USER")) (newline))))

$ gsi -:search=./modules demo.scm
Error: Missing command

demo: a small demo script

Usage: demo  <command> command-arg ...

Commands:
 hello                            say hello
 goodbye                          say goodbye
 help                             display help; help <command> for command help

$ gsi -:search=./modules demo.scm hello
hello, vyzo
$ gsi -:search=./modules demo.scm goodbye
goodbye, vyzo
```
