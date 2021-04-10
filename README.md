# ICR

TODO: Write a description here


## Installation

```sh
crystal build -p src/icr.cr
```
> You could also build it in release mode, but since icr is a test-version and it take a while to compile, it doesn't really worth it.

You should edit the file `icr-prelude.cr` and modify the require paths with the path
of the crystal standard lib (do `crystal env` and look CRYSTAL_PATH environment variable)
relatively to this file (absolute path are not supported yet :o)


## Usage

```sh
./icr
```
...and play :p

#### WARNING /!\\ :

* For now, std crystal lib is not included, so almost everything are missing, including the `puts` method, but primitive types and operations are available: (Int, Float, Tuple, NamedTuple, Symbol, Char), objects like String, Array or Pointers have been lazily implemented into the icr-prelude to serve mostly as 'prove of concept'.
* This first-version have *voluntary* memory leek, the memory allocated by `Array`, `String`, ... will be **NOT** free, see below for more details.
* Not all primitives and ASTNode have been implemented, so you should see lot of `BUG` or `TODO` messages, the most of them are normal at this stage of the project.

## How ICR works ?

ICR import the crystal compiler sources available in the standard library (hidden from the docs)
and parses the given input, executes the semantics on it, exactly like that:
```crystal
  def self.parse(text)
    ast_node = Crystal::Parser.parse text
    ast_node = @@program.normalize(ast_node)
    ast_node = @@program.semantic(ast_node)
    ast_node
  end
```
After that Crystal have done 80% of the works, it gives to ICR a fresh ast\_node, with already computed types and method on it (almost).

Then ICR runs through this ast\_node, and transmits ICRObjects (Wrapper for object created in ICR) depending the kind of the ast\_node.

A `BoolLiteral` is implemented like that:
```crystal
# This is the crystal ASTNode for a BoolLiteral, ICR will `run` on it.
class Crystal::BoolLiteral
  def run
    ICR.bool(self.value) # creates a ICRObject, containing the bool value
  end
end
```

And a `if` like that:
```crystal
class Crystal::If
  def run
    if self.cond.run.truthy? # runs thought the `cond` branch of this `if` (for example a BoolLiteral)
      self.then.run # and runs the branch `then` if the resulting ICRObject turns out to be truthy.
    else
      self.else.run
    end
  end
end
```

When ICR hits a primitive Node, (method that can't be implemented in crystal, like `+` operators or `object_id`), it reads the ICRObject as a true crystal type (Int32, UInt8,...), does the asked operation, and recreates a new ICRObject with the result.

Here is how addition is implemented, (so gives similar results to *true* crystal with all number kind):
```crystal
ICR.number(arg0.as_number + arg1.as_number) # create a ICRObject from a number
```

On the prompt, each time a code is written, the semantic is executed on the hole code written from the beginning (unless the errors), so the semantic will re-compute methods and vars declaration and write the name of a method will not give a "undefined method" error.

Then, only the written expression will be `run` by icr, and the resulting ICRObject will be displayed.

<!-- Well, it practice is is a bit more complicated of that, but i think you've got it. -->

#### Great, but what about Pointers and memory ?

Ok, the pointers was the difficult part. There are the basis of Array, String, Classes and actually the hole stdlib depend on them!

ICRObject actually contain a pointer to an certain among of data, (1 byte for UInt8, 4 bytes for Int32,...) and the value of the object is stored inside.

If this ICRObject represent a `Pointer(Int32)`, 4 bytes are allocated to store the address of this pointer. This address itself will point to the data of the pointer (allocated by the primitive malloc for example)

So, on a reading or a assignment of the pointer, data will be simply copied,
For example, on `pointer.value = 42`, 4 bytes of the `42` will be copied on the data of the pointer, and this will be possible whatever the nature of data (Int32, Struct, Class), only the size of data matter. And this size is always stored inside the ICRObject wrapper (with also the offsets of instances vars if any).

**The important think to know is that ICRObject will keep the binary representation of object, so low level code will give similar result.**

> Not really for now, because this first implementation doesn't rearrange the offset of ivars (alignment optimization) so it's like all classes an structs declared in ICR was `Packed`.

> Moreover, Union-types are not supported yet, and it's because the binary representation of a union  need more specific code to handle complex case (such as upcast and downcast,...). But this is "Work in progress!"

> However, the pointer allocated by ICRObjects (`Pointer` or Classes) become difficult to trace, and freeing theme require probably a Garbage Collector, may be there are a way to register theme by the *true* GC of the ICR-program, but this need more reflexion. That why this first version will **NOT** free the memory allocated by ICRObjects. (But don't worry, in practice this memory leek is not disturbing for small tests)


#### And for C-binding ??






## Contributing

1. Fork it (<https://github.com/your-github-user/icr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [I3oris](https://github.com/I3oris) - creator and maintainer
