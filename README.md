# IC

This repository is a **Test** for an implementation of an Interpreter Crystal.

IC will execute crystal code without never compile it. In addition of giving results fasted that compiling, IC offer a pretty shell like `irb`.

## Installation

You need to install the same dependencies as the crystal compiler, follow the instructions [here](https://github.com/crystal-lang/crystal/wiki/All-required-libraries).

Then:
```sh
git clone https://github.com/I3oris/ic.git

cd ic && make
```

## Usage

```sh
./ic
```
...and play :p

#### WARNING /!\\ :

* For now, standard crystal lib is not included, so almost everything is missing, including the `puts` method, but primitive types and operations are available: (Int, Float, Tuple, NamedTuple, Symbol, Char), objects like String, Array or Pointers have been lazily implemented into the ic-prelude to serve mostly as 'prove of concept'.
* Not all primitives and ASTNode have been implemented, so you should see a lot of `BUG` or `TODO` messages, the most of them are normal at this stage of the project.

#### Not implemented:
* some Primitives (in progress)
* Union Type (almost supported)
* raise
* ARGV, ENV, \`
* IO
* Proc (in progress)
* Lib
* Fibers
* ...

## Troubleshooting

### Installation

If you get an error `Undefined symbols for architecture x86_64: "llvm::AtomicCmpXchgInst::AtomicCmpXchgInst...` (#1), that mean your crystal compiler use a different version of llvm than this installed on your system. (check `crystal --version` and `llvm-config --version`)

To fix it, you can install the compiler from [sources](https://crystal-lang.org/install/from_sources/) (if it's not already done) and compile IC with it:
```sh
make COMPILER=path/to/crystal-compiler/bin/crystal
```

## How IC works?

IC import the crystal compiler sources available in the standard library, (hidden from the docs)
and parses the given input, executes the semantics on it, exactly like that:
```crystal
  def self.parse(text)
    ast_node = Crystal::Parser.parse text
    ast_node = @@program.normalize(ast_node)
    ast_node = @@program.semantic(ast_node)
    ast_node
  end
```
After that, Crystal has done 80% of work. It gives to IC a fresh ast\_node, with resolved types and methods for each node. (Macros are also executed in this time.)

Then, IC runs through this ast\_node, and transmits ICObjects (Wrapper for objects created in IC) depending the kind of the ast\_node.

A `BoolLiteral` is implemented like that:
```crystal
# This is the crystal ASTNode for a BoolLiteral, IC will `run` on it.
class Crystal::BoolLiteral
  def run
    IC.bool(self.value) # creates a ICObject, containing the bool value
  end
end
```

And a `if` like that:
```crystal
class Crystal::If
  def run
    if self.cond.run.truthy? # runs thought the `cond` branch of this `if` (for example a BoolLiteral)
      self.then.run # and runs the branch `then` if the resulting ICObject turns out to be truthy.
    else
      self.else.run
    end
  end
end
```

When IC hits a primitive Node, (method that can't be implemented in crystal, like `+` operators or `object_id`), it reads the ICObject as a true crystal type (Int32, UInt8,...), performs the asked operation, and recreates a new ICObject with the result.

Here is how addition is implemented (so gives similar results to *true* crystal with all number kind):
```crystal
IC.number(arg0.as_number + arg1.as_number) # create a ICObject from a number
```

At last, the final result is displayed, and a new input is asked, the informations from the previous lines (methods, Class, COSNT,...) are saved by Crystal because the same `@@program : Crystal::Program` is reused.

#### Great, but what about Pointers and memory ?

Ok, the pointers was the difficult part. There are the bases of Array, String, Classes and actually the hole stdlib depend on them!

ICObject contain in fact a pointer to a certain amount of data, (1 byte for UInt8, 4 bytes for Int32,...) and the value of the object is stored inside.

If this ICObject represents a `Pointer(Int32)`, 4 bytes are allocated to store the address of this pointer. This address itself will point to the data of the pointer (allocated by the primitive malloc for example)

So, on a reading or a assignment of the pointer, data will be simply copied.
For example, on `pointer.value = 42`, 4 bytes of the `42` will be copied on the data of the pointer, and this will be possible whatever the nature of data (Int32, Struct, Class), only the size of data matter. And this size is always stored inside the ICObject wrapper (with also the offsets of instances vars if any).

**The important think to know is that ICObject will keep the binary representation of object, so low level code will produce similar result.**

> Not really for now, because this first implementation doesn't rearrange the offset of ivars (no alignment) so it's like all classes and structs declared in IC was `Packed`.

## Contributing

1. Fork it (<https://github.com/I3oris/ic/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [I3oris](https://github.com/I3oris) - creator and maintainer
