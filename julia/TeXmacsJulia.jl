# 
#  TeXmacsJulia.jl
#  A TeXmacs plugin for the Julia language
#  (c) 2021  Massimiliano Gubinelli <mgubi@mac.com>
# 
#  This software falls under the GNU general public license version 3 or later.
#  It comes WITHOUT ANY WARRANTY WHATSOEVER. For details, see the file LICENSE
#  in the root directory or <http://www.gnu.org/licenses/gpl-3.0.html>.
#

#==============================================================================
Useful links:

* https://github.com/JuliaDocs/ANSIColoredPrinters.jl
* https://github.com/JuliaDocs/Documenter.jl/pull/1441
* https://docs.julialang.org/en/v1/stdlib/REPL/
* https://github.com/JuliaLang/julia/blob/28e63dc65a3ca3850ac2b530bd8a7a89cda551dc/base/version.jl
* https://juliagraphics.github.io/Luxor.jl/stable/moreexamples/
* https://github.com/JuliaLang/julia/blob/master/stdlib/REPL/docs/src/index.md

* https://github.com/JuliaLang/julia/issues/3744

* https://github.com/JuliaLang/IJulia.jl
* https://julia-doc.readthedocs.io/en/latest/

==============================================================================#

module TeXmacsJulia

import Base.Libc: flush_cstdio
import REPL: helpmode
import REPL.REPLCompletions: completions, completion_text
using REPL
import Markdown
import Base: AbstractDisplay, display, redisplay, catch_stack, show

const current_module = Ref{Module}(Main)
const orig_stdout = Ref{IO}(stdout)
const orig_stderr = Ref{IO}(stderr)
const read_stdout = Ref{Base.PipeEndpoint}()
const read_stderr = Ref{Base.PipeEndpoint}()
	
#=============================================================================#
## TeXmacs protocol

const DATA_BEGIN = Char(2)
const DATA_END = Char(5)
const DATA_ESCAPE = Char(27)
const DATA_COMMAND = Char(16)
const VERBATIM = "verbatim:"
const SCHEME = "scheme:"
const COMMAND = "command:"
const PROMPT = "prompt#"

texmacs_escape(data) = replace(replace(replace(data,
        DATA_ESCAPE => DATA_ESCAPE * DATA_ESCAPE),
        DATA_BEGIN => DATA_ESCAPE * DATA_BEGIN), 
        DATA_END => DATA_ESCAPE * DATA_END)
  
# TeXmacs expects all output to be bracketed in a DATA_BEGIN and DATA_END
# so that it can determines when the plugin ended the interaction        
tm_begin() = write(orig_stdout[], DATA_BEGIN, VERBATIM)
tm_end() = begin
    write(orig_stdout[],DATA_END)
    flush(orig_stdout[]) 
end

tm_out(data) = write(orig_stdout[], texmacs_escape(data))

tm_out(header, data) = begin
    write(orig_stdout[], 
        DATA_BEGIN, header, texmacs_escape(data), DATA_END)
    flush(orig_stdout[]) 
end

tm_err(header, data) = begin
    write(orig_stderr[], 
        DATA_BEGIN, header, texmacs_escape(data), DATA_END)
    flush(orig_stderr[]) 
end
#=============================================================================#
### Flush all redirected streams to TeXmacs

function flush_all()
    flush_cstdio() # flush writes to stdout/stderr by external C code
    flush(stdout)
    flush(stderr)
end

flush_output() = begin
    flush_all() # flush pending stdio
    local buf
    # add one more char so that we do not block on readavailable later
    write(stdout,"!")
    buf = String(readavailable(read_stdout[]));
    buf != "!" && tm_out(chop(buf) * "\n")
    write(stderr,"!")
    buf = String(readavailable(read_stderr[]));
    buf != "!" && tm_err(VERBATIM, chop(buf))
end

#=============================================================================#
### Stream redirection (from IJulia)

# create a wrapper type around redirected stdio streams,
# both for overloading things like `flush` and so that we
# can set properties like `color`.
struct TMJuliaStdio{IO_t <: IO} <: Base.AbstractPipe
    io::IOContext{IO_t}
end

TMJuliaStdio(io::IO, stream::AbstractString="unknown") =
    TMJuliaStdio{typeof(io)}(IOContext(io, :color=>false,
                            :texmacs_stream=>stream,
                            :displaysize=>displaysize()))
Base.pipe_reader(io::TMJuliaStdio) = io.io.io
Base.pipe_writer(io::TMJuliaStdio) = io.io.io
Base.lock(io::TMJuliaStdio) = lock(io.io.io)
Base.unlock(io::TMJuliaStdio) = unlock(io.io.io)
Base.in(key_value::Pair, io::TMJuliaStdio) = in(key_value, io.io)
Base.haskey(io::TMJuliaStdio, key) = haskey(io.io, key)
Base.getindex(io::TMJuliaStdio, key) = getindex(io.io, key)
Base.get(io::TMJuliaStdio, key, default) = get(io.io, key, default)
Base.displaysize(io::TMJuliaStdio) = displaysize(io.io)
Base.unwrapcontext(io::TMJuliaStdio) = Base.unwrapcontext(io.io)
Base.setup_stdio(io::TMJuliaStdio, readable::Bool) = Base.setup_stdio(io.io.io, readable)

if VERSION < v"1.7.0-DEV.254"
    for s in ("stdout", "stderr", "stdin")
        f = Symbol("redirect_", s)
        sq = QuoteNode(Symbol(s))
        @eval function Base.$f(io::TMJuliaStdio)
            io[:texmacs_stream] != $s && throw(ArgumentError(string("expecting ", $s, " stream")))
            Core.eval(Base, Expr(:(=), $sq, io))
            return io
        end
    end
end

#=============================================================================#
### display redirection

# need special handling for showing a string as a textmime
# type, since in that case the string is assumed to be
# raw data unless it is text/plain
israwtext(::MIME, x::AbstractString) = true
israwtext(::MIME"text/plain", x::AbstractString) = false
israwtext(::MIME, x) = false

# convert x to a string of type mime, making sure to use an
# IOContext that tells the underlying show function to limit output
function limitstringmime(mime::MIME, x)
    buf = IOBuffer()
    if israwtext(mime, x)
        return String(x)
    else
        show(IOContext(buf, :limit=>true, :color=>false), mime, x)
    end
    return String(take!(buf))
end

struct InlineDisplay <: AbstractDisplay end

showtofile(file::AbstractString, m::MIME, x) = begin
    open(file, "w") do io
        show(io, m, x)
    end
    tm_out("file:", file)
end

display(d::InlineDisplay, m::MIME"image/png", x) = 
    showtofile("$(ENV["TEXMACS_HOME_PATH"])/system/tmp/tmjulia_out_$(getpid()).png", m, x)

display(d::InlineDisplay, m::MIME"image/jpeg", x) = 
    showtofile("$(ENV["TEXMACS_HOME_PATH"])/system/tmp/tmjulia_out_$(getpid()).jpg", m, x)

display(d::InlineDisplay, m::MIME"application/pdf", x) = 
    showtofile("$(ENV["TEXMACS_HOME_PATH"])/system/tmp/tmjulia_out_$(getpid()).pdf", m, x)

display(d::InlineDisplay, m::MIME"text/html", x) = 
    tm_out("html:", limitstringmime(m, x))

display(d::InlineDisplay, m::MIME"text/latex", x) = 
    tm_out("latex:", limitstringmime(m, x))

display(d::InlineDisplay, m::MIME"text/markdown", x) = 
    display(d, MIME("text/html"), Markdown.html(x))

display(d::InlineDisplay, m::MIME"text/plain", s::AbstractString) = 
    tm_out(s)

# fallback
function display(d::InlineDisplay, m::MIME, x) 
    buf = IOBuffer()
    show(buf, m, x)
    tm_out(String(take!(buf)))
end

# generic display overloading

display(d::InlineDisplay, x::Markdown.MD) = display(d, MIME("text/markdown"), x) 

# default behaviour is showing text
function display(d::InlineDisplay, x)
    display(d, MIME("text/plain"), x)
#    tm_out("TODO: display an object of type [$(typeof(x))]")   
end

#=============================================================================#
### Some utilities

function banner()
    io = IOBuffer()
    Base.banner(io)
    tm_out(String(take!(io)))
end

function pdf_out(x) 
    if showable(MIME("application/pdf"), x)
        display(MIME("application/pdf"), x)
    else
        tm_out("[Cannot display PDF for $(typeof(x))]")
    end
end

function do_tab_complete(cmd::AbstractString)
    # syntax [DATA_COMMAND](complete [STRING] [CURSOR])
    try
        pos = 12
        arg1,pos = Meta.parse(cmd,pos; greedy=false) # [STRING]
        arg2,pos = Meta.parse(cmd,pos; greedy=false) # [CURSOR]
        if isa(arg1,AbstractString) && isa(arg2,Integer)
            ret,range,shouldcomplete = completions(arg1,arg2)
            compls = join(unique!(map(x -> "\"$(completion_text(x)[range.stop+2-range.start:end])\"",ret))," ")
            tm_out("scheme:", "(tuple \"$(arg1[range])\" $(compls))")
        end
    catch e 
        # ignore errors 
    end
end

#=============================================================================#
### Main loop

# we do not want to exit on SIGINT
# we can then catch InterruptException
Base.exit_on_sigint(false)

# redirect output/error
read_stdout[], = redirect_stdout()
redirect_stdout(TMJuliaStdio(stdout,"stdout"))
read_stderr[], = redirect_stderr()
redirect_stderr(TMJuliaStdio(stderr,"stderr"))
#redirect_stdin(TMJuliaStdio(stdin,"stdin"))

# redirect display
pushdisplay(InlineDisplay())

# print banner
tm_begin()
banner()
tm_out(PROMPT,">>> ")
tm_end()

# go
n = 0 # execution counter
ans = nothing # record last successful answer in ans

while true
    line = readline(stdin)
    length(line) == 0 && continue
    if line[1] == DATA_COMMAND
        # is tab completion the only possible command?
        do_tab_complete(line)
        continue
    end
    lines = []
    while line != "<EOF>"
        push!(lines, line)
        line = readline(stdin)
    end
    local code = join(lines,"\n")
    local result = nothing
    local err = nothing
    global ans = nothing
    tm_begin()
    try
        global n += 1
        # "; ..." cells are interpreted as shell commands for run
        code = replace(code, r"^\s*;.*$" =>
            m -> string(replace(m, r"^\s*;" => "Base.repl_cmd(`"),
                        "`, stdout)"))
        # a cell beginning with "? ..." is interpreted as a help request
        hcode = replace(code, r"^\s*\?" => "")
        # Let's try to run the input
        if hcode != code # help request
            buf = IOBuffer()
            help = Core.eval(Main, helpmode(buf, hcode))
            #flush_output()
            tm_out("HELP: $(String(take!(buf)))\n")
            display(help)
        else
            # finally run the code! 
            result = include_string(current_module[], code, "In[$n]")
            REPL.ends_with_semicolon(code) ? result = nothing : ans = result
        end
    catch e
        err = e
        result = catch_stack()
    end    

    # output
    try 
        if err != nothing 
            Base.invokelatest(Base.display_error, stderr, result)
        elseif result != nothing 
            Base.invokelatest(display, result)
            #show(stdout, result) # display the result as string
        end
    catch e 
        write(stdout, "Error showing values $(e)");
        Base.invokelatest(Base.display_error, stderr, catch_stack())
    end
    flush_output() # send all to texmacs
    tm_end()
end # while true

end # module TeXmacsJulia