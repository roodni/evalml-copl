open Printf

type ee = { store : Store.t; env : Value.env; expr : Expr.t }

let ee_to_string { store; env; expr } =
  let s_store =
    if Store.is_empty store then "" else Store.to_string store ^ " / "
  and s_env = (if env <> [] then Value.env_to_string env ^ " " else "") ^ "|- "
  and s_expr = Expr.to_string expr in
  s_store ^ s_env ^ s_expr

type ed = Value.t * Store.t

let ed_to_string (value, store) =
  Value.to_string value
  ^ if Store.is_empty store then "" else " / " ^ Store.to_string store

let ed_of_value value = (value, Store.empty)

module System = struct
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
    | EVar1
    | EVar2
    | ELet
    | EFun
    | EApp
    | ELetRec
    | EAppRec
    | EVar
    | EMult
    | BMult
    | EAssign
    | ERef
    | EDeref
    | ENil
    | ECons
    | EMatchNil
    | EMatchCons

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
    | EVar1 -> "E-Var1"
    | EVar2 -> "E-Var2"
    | ELet -> "E-Let"
    | EFun -> "E-Fun"
    | EApp -> "E-App"
    | ELetRec -> "E-LetRec"
    | EAppRec -> "E-AppRec"
    | EVar -> "E-Var"
    | EMult -> "E-Mult"
    | BMult -> "B-Mult"
    | EAssign -> "E-Assign"
    | ERef -> "E-Ref"
    | EDeref -> "E-Deref"
    | ENil -> "E-Nil"
    | ECons -> "E-Cons"
    | EMatchNil -> "E-MatchNil"
    | EMatchCons -> "E-MatchCons"

  type judgment =
    | EvalJ of { evalee : ee; evaled : ed }
    | PlusJ of int * int * int
    | MinusJ of int * int * int
    | TimesJ of int * int * int
    | LtJ of int * int * bool

  let judgment_to_string = function
    | EvalJ { evalee; evaled } ->
        sprintf "%s evalto %s" (ee_to_string evalee) (ed_to_string evaled)
    | PlusJ (l, r, s) -> sprintf "%d plus %d is %d" l r s
    | MinusJ (l, r, d) -> sprintf "%d minus %d is %d" l r d
    | TimesJ (l, r, p) -> sprintf "%d times %d is %d" l r p
    | LtJ (l, r, b) -> sprintf "%d less than %d is %b" l r b
end

module EDeriv = Deriv.Make (System)

exception Error of string * Expr.t

let eval mlver evalee =
  let open System in
  let rec eval evalee =
    let { store; env; expr } = evalee in
    let error s = raise @@ Error (s, expr) in
    let evaled, rule, premises =
      match expr with
      | Expr.Int i -> ((Value.Int i, store), EInt, [])
      | Expr.Bool b -> ((Value.Bool b, store), EBool, [])
      | Expr.If (c, t, f) ->
          let (cvalue, store), cderiv = eval { evalee with expr = c } in
          let retexpr, rule =
            match cvalue with
            | Value.Bool true -> (t, EIfT)
            | Value.Bool false -> (f, EIfF)
            | _ -> error "Condition must be bool"
          in
          let ret, retderiv = eval { evalee with store; expr = retexpr } in
          (ret, rule, [ cderiv; retderiv ])
      | Expr.BOp (((PlusOp | MinusOp | TimesOp | LtOp) as op), lexpr, rexpr)
        -> (
          let (lvalue, store), lderiv = eval { evalee with expr = lexpr } in
          let (rvalue, store), rderiv =
            eval { evalee with store; expr = rexpr }
          in
          match (lvalue, rvalue) with
          | Value.Int li, Value.Int ri ->
              let value, erule, bjudg, brule =
                match op with
                | PlusOp ->
                    let i = li + ri in
                    (Value.Int i, EPlus, PlusJ (li, ri, i), BPlus)
                | MinusOp ->
                    let i = li - ri in
                    (Value.Int i, EMinus, MinusJ (li, ri, i), BMinus)
                | TimesOp ->
                    let i = li * ri in
                    let erule, brule =
                      match mlver with
                      | Mlver.EvalRefML3 -> (EMult, BMult)
                      | _ -> (ETimes, BTimes)
                    in
                    (Value.Int i, erule, TimesJ (li, ri, i), brule)
                | LtOp ->
                    let b = li < ri in
                    (Value.Bool b, ELt, LtJ (li, ri, b), BLt)
                | _ -> assert false
              in
              ( (value, store),
                erule,
                [
                  lderiv;
                  rderiv;
                  EDeriv.{ concl = bjudg; rule = brule; premises = [] };
                ] )
          | _ -> error "Both arguments must be int" )
      | Expr.BOp (AssignOp, lexpr, rexpr) -> (
          let (lvalue, store), lderiv = eval { evalee with expr = lexpr } in
          let (rvalue, store), rderiv =
            eval { evalee with store; expr = rexpr }
          in
          match lvalue with
          | Value.Loc loc ->
              let store =
                try Store.assign store loc rvalue
                with Store.Invalid_reference -> error "Invalid reference"
              in
              ((rvalue, store), EAssign, [ lderiv; rderiv ])
          | _ -> error (sprintf "%s is not loc" (Expr.to_string lexpr)) )
      | Expr.Var v -> (
          match mlver with
          | EvalML1 | EvalML3 -> (
              match env with
              | (v', value) :: _ when v = v' -> (ed_of_value value, EVar1, [])
              | (_, _) :: tail ->
                  let evaled, premise = eval { evalee with env = tail } in
                  (evaled, EVar2, [ premise ])
              | [] -> error "Undeclared variable" )
          | EvalRefML3 | EvalML4 ->
              (* 1 step var *)
              let value =
                try List.assoc v env
                with Not_found -> error "Undeclared variable"
              in
              ((value, store), EVar, []) )
      | Expr.Let (v, e1, e2) ->
          let (value1, store), deriv1 = eval { evalee with expr = e1 } in
          let (value2, store), deriv2 =
            eval { store; env = (v, value1) :: env; expr = e2 }
          in
          ((value2, store), ELet, [ deriv1; deriv2 ])
      | Expr.Fun (v, e) -> ((Value.Fun (env, v, e), store), EFun, [])
      | Expr.App (e1, e2) -> (
          let (fval, store), fderiv = eval { evalee with expr = e1 } in
          let (aval, store), aderiv = eval { evalee with store; expr = e2 } in
          match fval with
          | Value.Fun (fenv, avar, fexpr) ->
              let evaled, deriv =
                eval { store; env = (avar, aval) :: fenv; expr = fexpr }
              in
              (evaled, EApp, [ fderiv; aderiv; deriv ])
          | Value.RecFun (fenv, fvar, avar, fexpr) ->
              let evaled, deriv =
                eval
                  {
                    store;
                    env = (avar, aval) :: (fvar, fval) :: fenv;
                    expr = fexpr;
                  }
              in
              (evaled, EAppRec, [ fderiv; aderiv; deriv ])
          | _ -> error (sprintf "%s cannot be applied" (Expr.to_string e1)) )
      | Expr.LetRec (f, a, e1, e2) ->
          let evaled, premise =
            eval
              {
                evalee with
                env = (f, Value.RecFun (env, f, a, e1)) :: env;
                expr = e2;
              }
          in
          (evaled, ELetRec, [ premise ])
      | Expr.Ref e ->
          let (value, store), premise = eval { evalee with expr = e } in
          let loc, store = Store.make_ref store value in
          ((Value.Loc loc, store), ERef, [ premise ])
      | Expr.Deref e -> (
          let (value, store), premise = eval { evalee with expr = e } in
          match value with
          | Value.Loc loc ->
              let value =
                try Store.deref store loc
                with Store.Invalid_reference -> error "Invalid reference"
              in
              ((value, store), EDeref, [ premise ])
          | _ -> error (sprintf "%s must be loc" (Expr.to_string e)) )
      | Expr.Nil -> (ed_of_value Value.Nil, ENil, [])
      | Expr.BOp (ConsOp, l, r) ->
          let (lvalue, _), lderiv = eval { evalee with expr = l } in
          let (rvalue, _), rderiv = eval { evalee with expr = r } in
          (ed_of_value @@ Value.Cons (lvalue, rvalue), ECons, [ lderiv; rderiv ])
      | Expr.Match (e1, clauses) -> (
          let (value, _), deriv1 = eval { evalee with expr = e1 } in
          match mlver with
          | EvalML4 -> (
              match clauses with
              | [
               (Expr.NilPat, e2);
               (Expr.ConsPat (Expr.VarPat x, Expr.VarPat y), e3);
              ] -> (
                  match value with
                  | Value.Nil ->
                      let (value, _), deriv2 = eval { evalee with expr = e2 } in
                      (ed_of_value value, EMatchNil, [ deriv1; deriv2 ])
                  | Value.Cons (v1, v2) ->
                      let (value, _), deriv3 =
                        eval
                          {
                            evalee with
                            env = (y, v2) :: (x, v1) :: env;
                            expr = e3;
                          }
                      in
                      (ed_of_value value, EMatchCons, [ deriv1; deriv3 ])
                  | _ -> error @@ sprintf "%s is not list" (Expr.to_string e1) )
              | _ -> assert false )
          | _ -> assert false )
    in
    (evaled, EDeriv.{ concl = EvalJ { evalee; evaled }; rule; premises })
  in
  eval evalee