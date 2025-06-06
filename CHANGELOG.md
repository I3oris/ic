# 0.9.0 (Wen May 14 2025)

### New
* Update to the last crystal version (1.16.3)
* Display code documentation on alt-d shortcut. Require reply version >= 0.4.

### Bugs fix
* Fix #25.

# 0.8.0 (Thu Jan 7 2025)

### New
* Update to the last crystal version (1.14.0)
* Clarify ambiguity with crystal version. (#22)
* Document the 'ctrl-enter' shortcut on windows.

### Bugs fix
* Allow auto-completion to work well when crossing '::'. Will be effective when Crystal with use the new version of REPLy and IC updated to this new version of Crystal.
* Fix #12.

### Internal
* Remove useless require. See #16.
* Fix shard markd not found anymore.

# 0.7.0 (Mon Apr 17 2023)

### New
* Update to the last crystal version (1.8.0).
* Now display `REPLy` version on `-v`.

### Internal
* Use `ameba` v1.4.3 and fix lint error.
* `REPLy` moved inside the compiler itself (in `./share/crystal-ic/lib`), it's not required as a shards anymore.

> Note: you can use `shards prune` to remove unused version of `REPLy`.

# 0.6.0 (Mon Nov 28 2022)

### New
* The history is now saved in `<home>/.ic_history`.
  * The file location can be controlled with the environment variables `IC_HISTORY_FILE`. (`IC_HISTORY_FILE=""` disables history saving)
  * History max size is 10_000. (Can be controlled with `IC_HISTORY_SIZE`)
* The new following hotkeys have been added: (thanks @zw963!)
  * `ctrl-d`: Delete char or exit (EOF).
  * `ctrl-k`: Delete after cursor.
  * `ctrl-u`: Delete before cursor.
  * `alt-backspace`/`ctrl-backspace`: Delete word after
  * `alt-d`/`ctrl-delete`: Delete word before.
  * `alt-f`/`ctrl-right`: Move word forward.
  * `alt-b`/`ctrl-left`: Move word backward.
  * `ctrl-n`/`ctrl-p`: Move cursor up/down.
  * `ctrl-b`/`ctrl-f`: Move cursor backward/forward.
* Behavior when auto-completing on only one match is slightly enhanced.
* Crystal interpreter version is now 1.6.2.

### Bugs fix
* Fix #9: repair require of local files, thanks  @lebogan!
* Fix display of auto-completion title on pry.
* Reduce blinking on ws-code (computation are now done before clearing the screen). Disallow `sync` and `flush_on_newline` during `update` which help to reduce blinking too, (#10), thanks @cyangle!
* Align the expression when prompt size change (e.g. line number increase), which avoid a cursor bug in this case.
* Fix wrong history index after submitting an empty entry.
* Fix ioctl window size magic number on darwin and bsd (reply#3), thanks @shinzlet!

### Internal
* Extract `repl_interface`/`expression_editor`/`char_reader`/`history` into a new shard `REPLy` and use it as dependency.
* Use ameba v1.3.1 and fix lint error.
* Use REPLy v0.3.1.

# 0.5.1 (Mon Sep 12 2022)

### New
* The auto-completion behavior is improved:
  * Now entries are narrowed as the user types.
  * Matching part of the name are now displayed in bright.
* Auto-completion is available on inner of `def` (Experimental)
  * It takes account of parameter types:
  ```cr
  def foo(a, b : String, c = 0, *args, **options)
    a.| # => Any
    b.| # => String
    c.| # => Int32
    args.| # => Tuple(Any)
    options. | # => NamedTuple()
  ```
  * It takes account of scope.
  * A new fictitious type `Any` is introduced, bypassing the semantics check on `Call`. (`foo(<Any>).bar.baz # => Any`)
  * The following is not yet supported:
    * Block parameter
    * Instance var parameter
    * Free vars
    * Class def
    * Def in generic type.
* Auto-completion now works inside a `Array`.
* Update to the last crystal version (1.5.1).

### Bugs fix
* Fix bad unindent on `include` (unindent still work for `in`).
* Fix broken auto-completion after `.class`.
* Fix broken auto-completion after a suffix `if`.

### Internal
* Fix wrong `CRYSTAL_PATH` in Makefile (preventing to add lib dependency).
* Remove some ameba excludes.

# 0.5.0 (Fry Jul 15 2022)

### New
* Implements auto-completion on Paths (`Foo::Bar::`)
* Improve error location, now display the correct location corresponding to prompt lines. Allow `pry` to display top-level frames.
* Add the `reset` command.
* Implement keyboard interruption on `ctrl-c`.
* Make interpreter installable via shard (Add postinstall script for shard), thanks @Vici37
* Implements shortcuts `home` and `end` to respectively move cursor to begin and end of  expression, thanks @Vici37.
* Load crystal stb in background during REPL startup, thanks @Vici37.
* Add a visual mark ('>') on auto-completion entries if `--no-color`.
* Allow usage of `NO_COLOR` environment (compliant to https://no-color.org).
* Update to the last crystal version (1.5.0)

### Bugs fix
* Don't colorize keyword methods, e.g. `42.class`
* Fix crash occurring on `require` auto-completion if current folder doesn't contain a `lib` folder.
* Fix wrong auto-indentation on parenthesized call.
* Fix color bug occurring on wrapped line on edge of view scroll.
* Fix bad display when `ctrl-c` an multiline expression.
* Fix missing `bin/` when using `make`.
* Fix broken `make release`.
* Fix #3: compile failed on local linux laptop (arch linux), thanks @zw963
* Fix `Invalid option: -v`, from https://github.com/crystal-lang/crystal/pull/12094.
* Fix already required files to not be removed from auto-completion entries.
* Fix bug auto-completing setter methods.
* Avoid insertion of control characters in editor, causing bad display.
* Prevent auto-completion while prelude is still loading. (Fix bug due to concurrent call)

### Other
* Allow comments to be in history.
* Ensure llvm-ext is built before 'make spec'.
*  Add 'make install' & 'make uninstall', make IC works independently of its position, also move `crystal-i` -> `share/crystal-ic`.
* Remove `--static` in release mode.
* Better handling if prompt change its size (line_number >= 1000).
* Improve performance when editing large expressions.
* Fix typo on invalid option.

### Internal
* Write spec for `History`/`AutoCompletionHandler`/`CharReader`/`ExpressionEditor`.
* Allow spec to test private methods
* Add some missing `private`.
* Make `CharReader` accept IO without `raw` mode.
* Make `ExpressionEditor`/ `AutoCompletionHandler`/`ReplInterface`/`Repl` output on any IO.
* Tiny refactor on `ReadChar.raw`.
* Small refactoring: remove static methods in IC to puts them directly to Repl. (Re)rename `main.cr` to `ic.cr`.
* Refactor `AutoCompletionHandler`.
* Refactor auto-completion (second time), allow it to trigger when editing long multiline expressions.
* Improve 'ExpressionEditor#expression_before_cursor'.
* Move `.dup` for a more semantically correct behavior.
* Update .ameba.yml
* Re-organize files.
* Compile with -Dpreview_mt flag.

# 0.4.1 (Sun May 8 2022)

### New
* Update to the last crystal version (1.4.1)
* Add option -d to trigger the debugger at starting.
* New auto-completion UI
  * Allow 'tabulation' to roll over completions entries.
  * Enhance the display and avoid remaining boilerplate output.
  * Add 'escape' key to close the auto-completion and 'shift-tab' to unroll entries.
  * Permit auto-completion to work on block arguments and on `&.foo`.
  * Allow auto-completion to work inside a def (argument names are not taken in account yet)
    Take also into account the current scope, the auto-completion now proposes 'property'/'getter'.. macros as their belong to the scope of a class.
  * Add macros to auto-completion
  * Implements auto-completion on require node
  * Enable auto-completion in debugger mode

* Change the 'insert new line' shortcut: 'crtl-o' -> 'alt-enter'

### Bugs fix
* Fix bug causing pry to not exit
* Fix coloration bug with named tuple keys
* Fix bug with `+=` causing error instead of going multiline
* Fix semantics bug caused by auto-completion
* Fix remaining boilerplate output when displaying auto-completion on multiline input
* Fix auto-completion not to trigger on `if`/`while` conditions and on `def` default values
* Raise syntax error on `[1 \n ,2` rather than get stuck in multiline mode
* Allow 'ctrl-tab' to work on tty
* Remove `[]`, `[]?`, `[]=` from operators coloration, so `[] of String` is colored correctly
* Remove llvm_ext.o causing it to not build on git clone
* Fix bug with pasting expression starting by '#'

### Other
* Some little cleaning.
* Update `.ameba.yml`
* Remove color from prompt for a sober style.
* Remove '\`' from auto-completion entries
* Add `llvm_ext.o` to gitignore
* Give precision about release build
* Fix typo in README
* Add a gif to README
* Add release build mode into makefile
* Add this changelog from commits history

# 0.3.2 (Sat Jan 22 2022)

### Commits
* Update to the last crystal-i version (1.3.2)
* Use ameba 0.14
* Refactor main entry
* Remove out-dated spec
* Update README
* Add more context to the auto-completion to allow more powerful auto-completions in the future.
* Fix infinite loop triggered on 'tab' for expression starting with dot
* Fix bug with auto-indent of methods with a block and proc-literal.
* Add `-D`/`--define` option
* Use option parser and add following options:
    * `--version`
    * `--help`
    * `--no-color`
* Move auto_completion code to its own file
* Add shortcuts for `step`, `next`, `finish` and `whereami` in pry
* Integrate pry!

# 0.3.0 (Sat Jan 8 2022)

### Commits
* Update to the last crystal-i version (1.3.0)
* Update to the last crystal-i version
* Reduce aliasing when displaying very large expressions
* Update highlighter colors
* Enhance display of auto-completions entries
* Experimental: Implement auto-completion (work on basic receiver `(\w+.)*`, but ignore the context (def vars, class/module context, ...) )
* Add shortcuts move_cursor_to_begin/move_cursor_to_end
* Doing some optimizations to reduce aliasing on very long expression
* Fix bug inserting a character before an "end" wrongly triggering auto-unindent
* Remove unused ic_prelude.cr
* Trigger correct scrolling when moving history up/down
* Trigger scrolling when cursor moves on border
* Now use crystal-i as back-end to interpret crystal. The previous work done to carry out an interpreter is still available on the `custom-interpreter` branch.

### Note
The project change his goal, it not aims to reproduce an interpreter, it aims to provide a nice interface to wrap crystal interpreter

# 0.2.1 (Fri Nov 12 2021)

### Commits
* Fix multiline not trigger on `begin\rescue`
* Fix highlighting bug with `(a+b)/x`, previously colored as regex
* Support proper behaviour on pasting code
* Fix some intern documentation misspellings
* Reduce screen aliasing on large expressions
* Fix bug while displaying full expression
* Support displaying expressions higher than term height
* Clean up + improve comments
* Update the multiline behaviour, now always submit on enter unless cursor is on the last line and the expression is unterminated. Add 'ctrl+o' shortcut to insert a new line otherwise.
* Rename REPLInterface module => ReplInterface
* Merge MultilineInput + CrystalMultilineInput classes => ReplInterface
* Implements correctly move_cursor_to_end_of_first_line when move down the history
* Fix to be compatible with crystal-1.2
* Don't discard editing when history is turn up
* Simplify cursor code
* Remove unused callback
* Implements move cursor down
* Enhance intern documentation
* Implements move_cursor_up
* Cleaning using the ameba tool (cyclomatic complexity = 30)
* Remake the interface from scratch, now supports:
    * editing mulitline, 'delete', 'back' end 'enter' can remove/add lines
    * moving cursor left and right
    * lines greater than term width, and resizing the term
    * auto-indent on parenthesizes, bracket, and almost all that need to be indented

    Doesn't supports yet:
    * moving cursor up and down
    * expression higher than term height
    * pasting large expressions
* update gitignore
* Ensure that IC run on 1.1.0
* Remove 'pending' on some already solved spec + minor fix
* Display arrays and ranges
* Remake ICObject to hold compile-time type (instead of runtime type)
    * Implement in a better way boxing/unboxing of unions
    * Implement more correctly Casts
    * Work on dispatch
    * Make pointerof(var_union) works
    * Display '∅' on invalid/uninitialized vars
* format spec
* repair specs by executing the prelude
* clean and split out specs
* Start to implement dispatch defs
* fix bug in error display
* fix bug with assignments
* fix:
    ```cr
    x = 42
    typeof(x) # => Int32
    x = foo
    typeof(x) # => String|Int32
    ```
* remove mis-formating
* catch interminated call
* Add a nice feature that replace `.foo` by `__.foo`

# 0.2.0 (Sat Jun 5 2021)

### Commits
* Support most of LibC, LibCG methods (not those with callback)
* Fix display bug on 'printf' or 'macro puts'
* support the 'out' keyword
* start implementing LibC fun
* fix error lines on macro errors
* fix bug with vars not cleared correctly between specs
* improve error messages and lines number
* add coloration for `&+=`, `&-=`, and `&*=`
* fix coloration bug with `1/2` and add coloration for operators `&-`, `&+`, ...
* Handle closure on receivers
* Handle closure on receivers
* Support procedures with closure! (normal vars)
* start supporting `ARGV`
* Support ivars initializers!
* fix bug with constants and cleaning
* Support class vars
* add  vars
* fix bug: use fullname on Const and Enums
* clean the code by getting ride of ICType (use Crystal::Type instead), and do some other cleaning
* work-around for #1
* remove a remaining 'puts'
* Finish Enums
* fix bug with integer generic var
* fix bug with integer generic var
* implements yield and blocks
* start implementing Enums
* add reset command
* Implements CONST
* Support all primitives in primitives.cr (unless proc_call)
* rename the project ICR -> IC
* add scenario 3
* update README
* Clarify some intern comments
* support CONST, now only the last written expression is parsed
* Add more specs
* Cleaning, and fix bugs with char and symbol comparisons
* add Alias
* add spawn keyword
* Catch more unterminated expressions
* fix bug with GC and memory corruption when union type are used!
* Clean the code, and progress on union and virtual types
* provide an informative README
* Fix bug with lines number inside string
* Support classes, and crystal_type_id,start to works on unions
* make the pointers works!, then add Char, String, Tuple, Symbol, and NamedTuple
* clean the code, simplify the primitive process, and support all integer kind
* Implements ICRObject in a way to support pointers on structs and pointer on classes
* support overload & default arguments on functions, but break `_`. Try to implements pointers
* improve shell, fix bug with highlighter and supports more ASTNodes
* update gitignore
* improve the command interface!

# 0.1.0
* ICR is coming!
