# tm-julia

A [TeXmacs](https://www.texmacs.org/tmweb/home/welcome.en.html) plugin for the [Julia](https://julialang.org) language

(c) 2021  Massimiliano Gubinelli <mgubi@mac.com>

This is still a development version lacking some features. Features request, bug reports and pull requests are welcome.

### TODO

* Better documentation
* Background computations
* Prettyprinting using TeXmacs formatting
* Syntax highlight in sessions (this will require to change the C++ sources)



### Installation

To use the plugin just clone this repository and create a symbolic link to it from `$TEXMACS_HOME_PATH/plugin/julia`

E.g. if you clone in $REPOSITORY_DIR then 
```
ln -s $REPOSITORY_DIR $TEXMACS_HOME_PATH/plugins/julia
```

You should then be able to insert a Julia session from the TeXmacs menu `Insert->Sessions->Julia`
