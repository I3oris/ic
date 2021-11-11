# IC

IC is an user-friendly interface for Interactive [Crystal](https://crystal-lang.org).

## Features

* All crystal-i capacities
* Syntax hightlighting
* Multiline input
* Auto formating
* Auto indentation
* History

## Warning

Crystal-i is experimental and not yet released, the imputed code is not guaranteed to work as expected. This repository is a preparation for this up-coming feature.

## Installation

### Dependencies

You need to install the same dependencies as the crystal compiler, follow the instructions [here](https://github.com/crystal-lang/crystal/wiki/All-required-libraries). If you have already installed crystal from source, you can skip this step.

### Build

```sh
git clone https://github.com/I3oris/ic.git

cd ic && make
```

## Usage

Interactive mode:
```sh
./ic
```

Run file with arguments:
```sh
./ic say_hello.cr World
```

### Shortcuts

* `ctrl-o` : On multiline input: insert a new line instead of submit edition.
* ... : more up-coming.

## Contributing

1. Fork it (<https://github.com/I3oris/ic/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [I3oris](https://github.com/I3oris) - creator and maintainer
