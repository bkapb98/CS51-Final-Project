(*
                         CS 51 Final Project
                         MiniML -- Evaluation
                             Spring 2018
*)

(* This module implements a small untyped ML-like language under
   various operational semantics.
 *)

open Expr ;;

(* Exception for evaluator runtime, generated by a runtime error *)
exception EvalError of string ;;
(* Exception for evaluator runtime, generated by an explicit "raise" construct*)
exception EvalException ;;


(*......................................................................
  Environments and values
 *)

module type Env_type = sig
    type env
    type value =
      | Val of expr
      | Closure of (expr * env)
    val create : unit -> env
    val close : expr -> env -> value
    val lookup : env -> varid -> value
    val extend : env -> varid -> value ref -> env
    val env_to_string : env -> string
    val value_to_string : ?printenvp:bool -> value -> string
  end

module Env : Env_type =
  struct
    type env = (varid * value ref) list
     and value =
       | Val of expr
       | Closure of (expr * env)

    (* Creates an empty environment *)
    let create () : env = [] ;;

    (* Creates a closure from an expression and the environment it's
       defined in *)
    let close (exp : expr) (env : env) : value =
      Closure (exp, env) ;;

    (* Looks up the value of a variable in the environment *)
    let lookup (env : env) (varname : varid) : value =
      try
        let _, y = List.find (fun (x, _) -> x = varname) env in !y
      with
        Not_found -> raise (EvalError "var not found") ;;

    (* Returns a new environment just like env except that it maps the
       variable varid to loc *)
    let extend (env : env) (varname : varid) (loc : value ref) : env =
      let new_env = List.remove_assoc varname env in
      (varname, loc) :: new_env ;;

    (* Returns a printable string representation of a value; the flag
       printenvp determines whether to include the environment in the
       string representation when called on a closure *)
    let rec value_to_string ?(printenvp : bool = true) (v : value) : string =
      match v with
      | Val x -> "Val " ^ exp_to_concrete_string x
      | Closure (x, loc) ->
        if printenvp then
          "(" ^ exp_to_concrete_string x ^ ", " ^ env_to_string loc ^ ")"
        else value_to_string (Val x)


    (* Returns a printable string representation of an environment *)
    and env_to_string (env : env) : string =
      match env with
      | [] -> ""
      | (x, loc) :: tl ->
        "(" ^ x ^ ", " ^ value_to_string !loc ^ ") " ^ env_to_string tl ;;
  end
;;


(*......................................................................
  Evaluation functions

  Returns a result of type value of evaluating the expression exp
  in the environment env. We've provided an initial implementation
  for a trivial evaluator, which just converts the expression
  unchanged to a value and returns it, along with "stub code" for
  three more evaluators: a substitution model evaluator and dynamic
  and lexical environment model versions.

  Each evaluator is of type expr -> Env.env -> Env.value for
  consistency, though some of the evaluators don't need an
  environment, and some will only return values that are "bare
  values" (that is, not closures). *)

(* The TRIVIAL EVALUATOR, which leaves the expression to be evaluated
   essentially unchanged, just converted to a value for consistency
   with the signature of the evaluators. *)

let eval_t (exp : expr) (_env : Env.env) : Env.value =
  (* coerce the expr, unchanged, into a value *)
  Env.Val exp ;;

(* I realized that unop, binop can be abstracted and used in both eval_s, eval_d
   so i took them out and wrote smaller functions for them *)
let unop_eval (u, e) : expr =
  match u with
  | Negate -> (match e with
               | Num x -> Num (~-x)
               | _ -> raise (EvalError "Invalid unop type"));;

let binop_eval (b, e, e1) : expr =
  match e, e1 with
  | Num y, Num z ->
    (match b with
     | Plus -> Num (y + z)
     | Minus -> Num (y - z)
     | Times -> Num (y * z)
     | Divide -> Num (y / z)
     | Equals -> Bool (y = z)
     | LessThan -> Bool (y < z)
     | GreaterThan -> Bool (y > z))
  | Bool y, Bool z ->
    (match b with
     | Equals -> Bool (y = z)
     | LessThan -> Bool (y < z)
     | GreaterThan -> Bool (y > z)
     | _ -> raise (EvalError "This binop can not be used with type Bool"))
  | _ -> raise (EvalError "Binop's only evaluate with Nums or Bools");;

(* The SUBSTITUTION MODEL evaluator -- to be completed *)
(* added helper function so that I can return expr and not deal with values *)
let eval_s (exp : expr) (_env : Env.env) : Env.value =
  let rec help (exp : expr) : expr =
  match exp with
  | Var _ -> raise (EvalError "Doesn't evaluate")
  | Num _  | Bool _ | Fun _ -> exp
  | Unop (u, e) -> unop_eval (u, help e)
  | Binop (b, e, e1) -> binop_eval (b, help e, help e1)
  | Conditional (e, e1, e2) ->
    (match help e with
     | Bool x -> if x then help e1 else help e2
     | _ -> raise (EvalError "first term of conditional must be bool"))
  | Let (x, e, e1) -> help (subst x (help e) e1)
  | Letrec (x, e, e1) ->
      help (subst x (help (subst x (Letrec (x, e, (Var x))) e)) e1)
  | Raise -> raise (EvalError "raise")
  | Unassigned -> raise (EvalError "unassigned")
  | App (e, e1) ->
    (match help e with
     | Fun (x, e2) -> help (subst x (help e1) e2)
     | _ -> raise (EvalError "invalid use of app"))
  in Env.Val (help exp) ;;

(* important for lexical scoping *)
let val_to_exp (v : Env.value) : expr =
  match v with
  | Val x -> x
  | Closure (x, _) -> x ;;

(* The DYNAMICALLY-SCOPED ENVIRONMENT MODEL evaluator -- to be
   completed *)
(* added helper function so that I can return expr and not deal with values *)
let eval_d (exp : expr) (env : Env.env) : Env.value =
  let rec help (exp : expr) (env : Env.env) : expr =
    match exp with
    | Var x -> val_to_exp (Env.lookup env x)
    | Num _  | Bool _ | Fun _ | Unassigned -> exp
    | Unop (u, e) -> unop_eval (u, (help e env))
    | Binop (b, e, e1) -> binop_eval (b, (help e env), (help e1 env))
    | Conditional (e, e1, e2) ->
      (match help e env with
       | Bool x -> if x then help e1 env else help e2 env
       | _ -> raise (EvalError "first term of conditional must be bool"))
    | Let (x, e, e1) -> help e1 (Env.extend env x (ref (Env.Val (help e env))))
    | Letrec (x, e, e1) ->
        help e1 (Env.extend env x (ref (Env.Val
        (help e (Env.extend env x (ref (Env.Val Unassigned)))))))
    | Raise -> raise (EvalError "raise")
    | App (e, e1) ->
      (match help e env with
       | Fun (x, e2) -> help e2 (Env.extend env x (ref (Env.Val (help e1 env))))
       | _ -> raise (EvalError "invalid use of app"))
  in Env.Val (help exp env) ;;


(* The LEXICALLY-SCOPED ENVIRONMENT MODEL evaluator -- optionally
   completed as (part of) your extension *)

let rec eval_l (exp : expr) (env : Env.env) : Env.value =
  match exp with
  | Var x -> Env.lookup env x
  | Num _  | Bool _ | Unassigned -> Env.Val exp
  | Unop (u, e) -> Env.Val (unop_eval (u, val_to_exp (eval_l e env)))
  | Binop (b, e, e1) -> Env.Val
    (binop_eval (b, val_to_exp (eval_l e env), val_to_exp (eval_l e1 env)))
  | Conditional (e, e1, e2) ->
    (match eval_l e env with
     | Val (Bool x) -> if x then eval_l e1 env else eval_l e2 env
     | _ -> raise (EvalError "first term of conditional must be bool"))
  | Fun _ -> Env.close exp env
  | Let (x, e, e1) -> eval_l e1 (Env.extend env x (ref (eval_l e env)))
  | Letrec (x, e, e1) ->
    let rf = ref (Env.Val Unassigned) in
      let env_b = Env.extend env x rf in
        rf := (eval_l e env_b) ;
        eval_l e1 env_b
  | Raise -> raise (EvalError "raise")
  | App (e, e1) ->
    (match eval_l e env with
     | Closure (Fun (x, e2), env_b) ->
        eval_l e2 (Env.extend env_b x (ref (eval_l e1 env)))
     | _ -> raise (EvalError "invalid use of app")) ;;

(* Connecting the evaluators to the external world. The REPL in
   miniml.ml uses a call to the single function evaluate defined
   here. Initially, evaluate is the trivial evaluator eval_t. But you
   can define it to use any of the other evaluators as you proceed to
   implement them. (We will directly unit test the four evaluators
   above, not the evaluate function, so it doesn't matter how it's set
   when you submit your solution.) *)

let evaluate = eval_t ;;
