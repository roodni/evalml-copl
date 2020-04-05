open Expr
open Value
open Printf

type rule =
  | EInt
  | EBool
  | EIfT
  | EIfF
  | EPlus
  | EMinus
  | ETimes
  | ELt
  | BPlus
  | BMinus
  | BTimes
  | BLt
  | EVar
  | ELet
  | EFun
  | EApp
  | ELetRec
  | EAppRec

let rule_to_string = function
  | EInt -> "E-Int"
  | EBool -> "E-Bool"
  | EIfT -> "E-IfT"
  | EIfF -> "E-IfF"
  | EPlus -> "E-Plus"
  | EMinus -> "E-Minus"
  | ETimes -> "E-Times"
  | ELt -> "E-Lt"
  | BPlus -> "B-Plus"
  | BMinus -> "B-Minus"
  | BTimes -> "B-Times"
  | BLt -> "B-Lt"
  | EVar -> "E-Var"
  | ELet -> "E-Let"
  | EFun -> "E-Fun"
  | EApp -> "E-App"
  | ELetRec -> "E-LetRec"
  | EAppRec -> "E-AppRec"

type judgment =
  | EvalJ of { evalee : Evaluatee.t; value : value }
  | PlusJ of int * int * int
  | MinusJ of int * int * int
  | TimesJ of int * int * int
  | LtJ of int * int * bool

let judgment_to_string = function
  | EvalJ { evalee; value } ->
      sprintf "%s evalto %s"
        (Evaluatee.to_string evalee)
        (value_to_string value)
  | PlusJ (l, r, s) -> sprintf "%d plus %d is %d" l r s
  | MinusJ (l, r, d) -> sprintf "%d minus %d is %d" l r d
  | TimesJ (l, r, p) -> sprintf "%d times %d is %d" l r p
  | LtJ (l, r, b) -> sprintf "%d less than %d is %b" l r b

type t = { concl : judgment; rule : rule; premises : t list }

let rec output ?(indent = 0) ?(outchan = stdout) { premises; rule; concl } =
  let printf f = fprintf outchan f in
  let rec output_indent depth =
    if depth > 0 then (
      printf "  ";
      output_indent (depth - 1) )
  in
  output_indent indent;
  printf "%s by %s " (judgment_to_string concl) (rule_to_string rule);
  if premises = [] then printf "{};\n"
  else (
    printf "{\n";
    List.iter (fun deriv -> output ~indent:(indent + 1) ~outchan deriv) premises;
    output_indent indent;
    printf "};\n" )

exception EvalError of string

let rec eval evalee =
  let Evaluatee.{ env; expr } = evalee in
  let value, rule, premises =
    match expr with
    | IntExp i -> (IntVal i, EInt, [])
    | BoolExp b -> (BoolVal b, EBool, [])
    | IfExp (c, t, f) ->
        let cvalue, cderiv = eval { evalee with expr = c } in
        let retexpr, rule =
          match cvalue with
          | BoolVal true -> (t, EIfT)
          | BoolVal false -> (f, EIfF)
          | _ -> raise (EvalError "condition must be boolean: if")
        in
        let retvalue, retderiv = eval { evalee with expr = retexpr } in
        (retvalue, rule, [ cderiv; retderiv ])
    | BOpExp (((PlusOp | MinusOp | TimesOp | LtOp) as op), lexpr, rexpr) -> (
        let lvalue, lderiv = eval { evalee with expr = lexpr }
        and rvalue, rderiv = eval { evalee with expr = rexpr } in
        match (lvalue, rvalue) with
        | IntVal li, IntVal ri ->
            let value, erule, bjudg, brule =
              match op with
              | PlusOp ->
                  let i = li + ri in
                  (IntVal i, EPlus, PlusJ (li, ri, i), BPlus)
              | MinusOp ->
                  let i = li - ri in
                  (IntVal i, EMinus, MinusJ (li, ri, i), BMinus)
              | TimesOp ->
                  let i = li * ri in
                  (IntVal i, ETimes, TimesJ (li, ri, i), BTimes)
              | LtOp ->
                  let b = li < ri in
                  (BoolVal b, ELt, LtJ (li, ri, b), BLt)
            in
            ( value,
              erule,
              [ lderiv; rderiv; { concl = bjudg; rule = brule; premises = [] } ]
            )
        | _ ->
            raise
              (EvalError
                 ("both arguments must be integer: " ^ binop_to_string op)) )
    | VarExp v ->
        let index = Var.to_int v - 1 in
        ( ( try List.nth env index
            with Failure _ ->
              raise (EvalError ("Not found: " ^ Var.to_string v)) ),
          EVar,
          [] )
    | LetExp (e1, e2) ->
        let value1, deriv1 = eval { evalee with expr = e1 } in
        let value2, deriv2 = eval { env = value1 :: env; expr = e2 } in
        (value2, ELet, [ deriv1; deriv2 ])
    | FunExp e -> (FunVal (env, e), EFun, [])
    | AppExp (e1, e2) -> (
        let fval, fderiv = eval { evalee with expr = e1 }
        and aval, aderiv = eval { evalee with expr = e2 } in
        match fval with
        | FunVal (fenv, fexpr) ->
            let value, deriv = eval { env = aval :: fenv; expr = fexpr } in
            (value, EApp, [ fderiv; aderiv; deriv ])
        | RecFunVal (fenv, fexpr) ->
            let value, deriv =
              eval { env = aval :: fval :: fenv; expr = fexpr }
            in
            (value, EAppRec, [ fderiv; aderiv; deriv ])
        | _ ->
            raise
              (EvalError (sprintf "%s cannot be applied" (value_to_string fval)))
        )
    | LetRecExp (e1, e2) ->
        let value, premise =
          eval { env = RecFunVal (env, e1) :: env; expr = e2 }
        in
        (value, ELetRec, [ premise ])
  in
  (value, { concl = EvalJ { evalee; value }; rule; premises })
