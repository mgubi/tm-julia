
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; MODULE      : init-julia.scm
;; DESCRIPTION : Initialize the julia plugin
;; COPYRIGHT   : (C) 2021 Massimiliano Gubinelli
;;
;; This software falls under the GNU general public license version 3 or later.
;; It comes WITHOUT ANY WARRANTY WHATSOEVER. For details, see the file LICENSE
;; in the root directory or <http://www.gnu.org/licenses/gpl-3.0.html>.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (julia-serialize lan t)
    (with u (pre-serialize lan t)
      (with s (texmacs->code (stree->tree u) "SourceCode")
        (string-append s "\n<EOF>\n"))))

(define (julia-entry)
  (system-url->string
    (if (url-exists? "$TEXMACS_HOME_PATH/plugins/julia/julia/TeXmacsJulia.jl")
       "$TEXMACS_HOME_PATH/plugins/julia/julia/TeXmacsJulia.jl"
       "$TEXMACS_PATH/plugins/julia/julia/TeXmacsJulia.jl")))

(define (julia-launcher)
  (with boot (raw-quote (julia-entry))
    (if (url-exists-in-path? "julia")
        (string-append "julia " boot)
        (string-append "julia " boot))))

(plugin-configure julia
  (:winpath "Julia" "bin")
  (:macpath "Julia*" "Contents/Resources/julia/bin")
  (:require (url-exists-in-path? "julia"))
  (:serializer ,julia-serialize)
  (:launch ,(julia-launcher))
  (:tab-completion #t)
  (:session "Julia"))

(when (supports-julia?)
  (plugin-input-converters julia))
