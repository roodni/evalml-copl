open Base

type t = ML1 | ML3 | RefML3 | ML4 | ML5

val to_string : t -> string

exception Error of t * t

val detect : ?store:Store.t -> ?env:Value.env -> Expr.t -> t