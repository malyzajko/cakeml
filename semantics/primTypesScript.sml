(*Generated by Lem from primTypes.lem.*)
open HolKernel Parse boolLib bossLib;
open lem_pervasivesTheory libTheory astTheory ffiTheory semanticPrimitivesTheory bigStepTheory;

val _ = numLib.prefer_num();



val _ = new_theory "primTypes"

(*open import Pervasives*)
(*open import Ast*)
(*open import SemanticPrimitives*)
(*open import Ffi*)
(*open import BigStep*)
(*open import Lib*)

(*val prim_types_program : prog*)
val _ = Define `
 (prim_types_program =  
([Tdec (Dexn "Bind" []);
   Tdec (Dexn "Chr" []);
   Tdec (Dexn "Div" []);
   Tdec (Dexn "Subscript" []);
   Tdec (Dtype [([], "bool", [("true", []); ("false", [])])]);
   Tdec (Dtype [(["'a"], "list", [("nil", []); ("::", [Tvar "'a"; Tapp [Tvar "'a"] (TC_name (Short "list"))]) ])]);
   Tdec (Dtype [(["'a"], "option", [("NONE", []);("SOME", [Tvar "'a"]) ])]) ]))`;


(*val add_to_sem_env : forall 'ffi. Eq 'ffi => (state 'ffi * environment v) -> prog -> maybe (state 'ffi * environment v)*)
val _ = Define `
 (add_to_sem_env (st, env) prog =  
(let res = ({ res | res | evaluate_whole_prog F env st prog res }) in
    if res = {} then
      NONE
    else
      (case CHOICE res of
        (st', new_ctors, Rval (new_mods, new_vals)) =>
        SOME (st', extend_top_env new_mods new_vals new_ctors env)
      | _ => NONE
      )))`;


(*val prim_sem_env : forall 'ffi. Eq 'ffi => ffi_state 'ffi -> maybe (state 'ffi * environment v)*)
val _ = Define `
 (prim_sem_env ffi =  
(add_to_sem_env
    (<| clock :=( 0); ffi := ffi; refs := []; defined_mods := {}; defined_types := {} |>,
     <| m := []; c := ([],[]); v := [] |>)
        prim_types_program))`;

val _ = export_theory()
