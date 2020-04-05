open Printf

type binOp = PlusOp | MinusOp | TimesOp | LtOp

let binop_to_string = function
  | PlusOp -> "+"
  | MinusOp -> "-"
  | TimesOp -> "*"
  | LtOp -> "<"

type expr =
  | IntExp of int
  | BoolExp of bool
  | BOpExp of binOp * expr * expr
  | IfExp of expr * expr * expr
  | VarExp of Var.t
  | LetExp of expr * expr
  | FunExp of expr
  | AppExp of expr * expr
  | LetRecExp of expr * expr

let rec expr_to_string = function
  | IntExp i -> string_of_int i
  | BoolExp b -> string_of_bool b
  | BOpExp (op, l, r) ->
      sprintf "(%s %s %s)" (expr_to_string l) (binop_to_string op)
        (expr_to_string r)
  | IfExp (c, t, f) ->
      sprintf "(if %s then %s else %s)" (expr_to_string c) (expr_to_string t)
        (expr_to_string f)
  | VarExp v -> Var.to_string v
  | LetExp (e1, e2) ->
      sprintf "(let . = %s in %s)" (expr_to_string e1) (expr_to_string e2)
  | FunExp e -> sprintf "(fun . -> %s)" (expr_to_string e)
  | AppExp (l, r) -> sprintf "(%s %s)" (expr_to_string l) (expr_to_string r)
  | LetRecExp (e1, e2) ->
      sprintf "(let rec . = fun . -> %s in %s)" (expr_to_string e1)
        (expr_to_string e2)
