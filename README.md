# blink-cmp-dat-word

[![Unit Tests](https://github.com/xieyonn/blink-cmp-dat-word/actions/workflows/test.yaml/badge.svg?branch=main)](https://github.com/xieyonn/blink-cmp-dat-word/actions/workflows/test.yaml)

Fast, offline word source for [blink.cmp](https://github.com/Saghen/blink.cmp). Pure Lua, no other dependencies.

<img src="data/preview.png" alt="Preview Image" width="580">

## Features

- Fast
    - Use [Double-Array Tire](https://linux.thai.net/~thep/datrie/datrie.html) data structure to build the word completion source, with query time < 0.1 ms.
    - Use binary file for serialization, only rebuilt when the word source file is updated.
- Async: All operations are performed asynchronously and will never block.
- Limited spell-suggest: Help correct minor spelling mistakes.

## Requirements

- neovim >= v0.11.0
- [blink.cmp](https://github.com/Saghen/blink.cmp)

## Quick Start

Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
return {
  {
    "saghen/blink.cmp",
    dependencies = {
      "xieyonn/blink-cmp-dat-word",
    },
    opts = {
      sources = {
        default = {
          -- ...
          "datword", -- add datword to default sources
        },
        providers = {
          -- add datword provider
          datword = {
            name = "DatWord",
            module = "blink-cmp-dat-word",
            opts = {
              paths = {
                -- "path_to_your_words.txt", -- add your owned word files before dictionary.
                "/usr/share/dict/words", -- This file is included by default on Linux/macOS.
              },
            },
          },
        },
      },
    },
  },
}
```

> Query words in order of `opts.paths`, add custom words file before dictionary files.

## Options

Options are defined in `blink.cmp`, config path: `sources.provider.datword.opts`

```lua
opts = {
  paths = { "path_to_your_words" }, -- word source file paths.
  build_command = "" -- Define a Command to rebuild words, eg: `BuildDatWord`, then use `BuildDatWord!` to force rebuild.
  spellsuggest = false,-- Enable limited spellsuggest. eg: enter `thsi` give you `this`
}
```

## Word Source Files

Recommends:

- [Google-10000-english](https://github.com/first20hours/google-10000-english) 10k most common English words.
- `/usr/share/dict/words` is a standard system file on Unix-like OSes containing a large list of English words, one per line.

Or add your own word list, with one word per line.

## Related Projects

- [blink-cmp-dictionary](https://github.com/Kaiser-Yang/blink-cmp-dictionary) Use external tools `fzf` or `ag` to search text files.
- [blink-cmp-words](https://github.com/archie-judd/blink-cmp-words) Use external tool `fzf` to search a formated file, also support thesaurus.

Inspired by [cmp-dictionary](https://github.com/uga-rosa/cmp-dictionary).
