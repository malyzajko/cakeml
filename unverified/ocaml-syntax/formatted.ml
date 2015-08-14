open Batteries
open BatResult.Monad

open Asttypes
open Ident
open Path
open Types
open Typedtree
open TypedtreeMap

open FormatDecl
open Preprocessor

let rec mapM f = function
  | [] -> return []
  | x :: xs -> f x >>= fun y ->
               mapM f xs >>= fun ys ->
               return (y :: ys)

let mapiM f =
  let rec g i = function
    | [] -> return []
    | x :: xs -> f i x >>= fun y ->
                 g (succ i) xs >>= fun ys ->
                 return (y :: ys)
  in
  g 0

(* Flipped map for monads *)
let ( <&> ) x f = x >>= return % f
let ( <$> ) f x = x <&> f

let indent = 2

let cut = Break (0, 0)
let sp = Break (1, 0)

let paren s =
  Box (Hovp, 0, [Lit "("; s; cut; Lit ")"])

let id x = x
let ifThen x f = if x then f else id

let indent_by = BatString.repeat "  "

type assoc = Neither | Left | Right
type fixity = assoc * int

let starts_with_any starts str =
  BatList.exists (fun s -> BatString.starts_with s str) starts

let fixity_of = function
  | x when BatString.starts_with "!" x
        || (BatString.length x >= 2 && starts_with_any ["?"; "~"] x) ->
    Neither, 0
  | "." | ".(" | ".[" | ".{" -> Neither, 1
  | "#" -> Neither, 2
  | " " -> Left, 3
  | "-" | "-." -> Neither, 4
  | "lsl" | "lsr" | "asr" -> Right, 5
  | x when BatString.starts_with "**" x -> Right, 5
  | "mod" | "land" | "lor" | "lxor" -> Left, 6
  | x when starts_with_any ["*"; "/"; "%"] x -> Left, 6
  | x when starts_with_any ["+"; "-"] x -> Left, 7
  | "::" -> Right, 8
  | x when starts_with_any ["@"; "^"] x -> Right, 9
  | "!=" -> Left, 10
  | x when starts_with_any ["="; "<"; ">"; "|"; "&"; "$"] x -> Left, 10
  | "&" | "&&" -> Right, 11
  | "||" | "or" -> Right, 12
  | "," -> Neither, 13
  | "<-" | ":=" -> Right, 14
  | "if" -> Neither, 15
  | ";" -> Right, 16
  | "let" | "match" | "fun" | "function" | "try" -> Neither, 17
  | _ -> Neither, ~-1

let fix_identifier = function
  | ("abstype" | "andalso" | "case" | "datatype" | "eqtype" | "fn" | "handle"
    | "infix" | "infixr" | "local" | "nonfix" | "op" | "orelse" | "raise"
    | "sharing" | "signature" | "structure" | "where" | "withtype" | "div"
    | "SOME" | "NONE" | "oc_mod" | "oc_ref" | "oc_raise" | "Oc_Array")
    as x ->
    x ^ "__"
  | "Some" -> "SOME"
  | "None" -> "NONE"
  | "Array" -> "Oc_Array"
  | x when BatString.starts_with "_" x -> "u" ^ x
  | x when
    (match fixity_of x with
    | Neither, _ -> false
    | _ -> true
    ) -> "op" ^ x
  | x -> x

let fix_var_name = fix_identifier
let fix_type_name = fix_identifier

let fix_formatted_identifier = function
  | Lit s -> Lit (fix_identifier s)
  | x -> x

let rec convertPervasive : string -> string =
  let rec f : char list -> string list = function
    | [] -> []

    | '=' :: xs -> "equals" :: f xs
    | '<' :: xs -> "lt" :: f xs
    | '>' :: xs -> "gt" :: f xs

    | '&' :: xs -> "amp" :: f xs
    | '|' :: xs -> "bar" :: f xs

    | '@' :: xs -> "at" :: f xs

    | '~' :: xs -> "tilde" :: f xs
    | '+' :: xs -> "plus" :: f xs
    | '-' :: xs -> "minus" :: f xs
    | '*' :: xs -> "star" :: f xs
    | '/' :: xs -> "slash" :: f xs

    | '^' :: xs -> "hat" :: f xs

    | '!' :: xs -> "bang" :: f xs
    | ':' :: xs -> "colon" :: f xs

    | ['m'; 'o'; 'd'] -> ["oc_mod"]
    | ['r'; 'a'; 'i'; 's'; 'e'] -> ["oc_raise"]
    | ['r'; 'e'; 'f'] -> ["oc_ref"]

    | xs -> [BatString.of_list xs]
  in
  BatString.concat "_" % f % BatString.to_list

let rec print_longident_pure = function
  | Longident.Lident ident -> Lit (fix_identifier ident)
  | Longident.Ldot (left, right) ->
    let left = print_longident_pure left in
    let right = ifThen (left = Lit "Pervasives") convertPervasive right in
    Box (H, indent, [left; cut; Lit "."; Lit right])
  | Longident.Lapply (p0, p1) ->
    Box (H, indent, [print_longident_pure p0; sp; print_longident_pure p1])

let print_longident = return % print_longident_pure

let rec longident_of_path = function
  | Pident i -> Longident.Lident i.name
  | Pdot (l, r, _) -> Longident.Ldot (longident_of_path l, r)
  | Papply (l, r) ->
    Longident.Lapply (longident_of_path l, longident_of_path r)

let print_path_pure = print_longident_pure % longident_of_path
let print_path = print_longident % longident_of_path

let print_constant = function
  | Const_int x -> Lit (string_of_int x)
  | Const_char x -> Lit ("#\"" ^ BatChar.escaped x ^ "\"")
  | Const_string (x, y) -> Lit ("\"" ^ BatString.escaped x ^ "\"")
  | Const_float x -> Lit x
  | Const_int32 x -> Lit (BatInt32.to_string x)
  | Const_int64 x -> Lit (BatInt64.to_string x)
  | Const_nativeint x -> Lit (BatNativeint.to_string x)

(* Precedence rules (for parenthesization):
   Low number => loose association
   0: case expression, case pattern, let expression, if condition,
      tuple term, list term
   1: Case RHS
   2: Application

   case x of
     p => ...
   | q => (case y of ...)
   | r => ...
 *)

let rec path_prefix = function
  | Pident _ -> Lit ""
  | Pdot (p, _, _) -> Box (H, indent, [print_path_pure p; cut; Lit "."])
  | Papply (p, _) -> Box (H, indent, [print_path_pure p; sp])

(* Constructors don't have a fully specified path. Infer it from the type. *)
let make_constructor_path { cstr_name; cstr_res = { desc; }; } =
  match desc with
  | Tconstr (p, _, _) ->
    return @@ Box (H, 0, [path_prefix p; Lit cstr_name])
  | _ -> Bad ("Can't deduce path of constructor " ^ cstr_name)

let rec intersperse x = function
  | [] -> []
  | [y] -> [y]
  | y :: ys -> y :: x :: intersperse x ys

let rec intersperseMany xs = function
  | [] -> []
  | [y] -> [y]
  | y :: ys -> y :: xs @ intersperseMany xs ys

let print_tupled xs = paren @@ Box (Hovp, 0, intersperseMany [Lit ","; sp] xs)

let print_construct prec (f : int -> 'a -> (format_decl, string) result)
                    cstr (xs : 'a list) =
  match cstr.cstr_name, xs with
  | "::", [x; y] ->
    f 1 x >>= fun x' ->
    f 0 y >>= fun y' ->
    return @@ ifThen (prec > 0) paren @@
      Box (Hovs, indent, [x'; sp; Lit "::"; sp; y'])
  | _ ->
    make_constructor_path cstr >>= fun name ->
    (match xs with
    | [] -> return @@ Lit ""
    | [x] -> f 2 x >>= fun x' ->
             return @@ Box (Hovp, 0, [sp; x'])
    | _ -> mapM (f 0) xs >>= fun xs' ->
           return @@ Box (Hovp, 0, [sp; print_tupled xs'])
    ) >>= fun args ->
    return @@ ifThen (prec > 1 && not ([] = xs)) paren @@
      Box (Hovp, indent, [fix_formatted_identifier name; args])

let rec print_pattern prec pat =
  match pat.pat_desc with
  (* _ *)
  | Tpat_any -> return @@ Lit "unused__"
  | Tpat_var (ident, name) -> return @@ Lit (fix_var_name name.txt)
  | Tpat_constant c -> return @@ print_constant c
  | Tpat_tuple ps -> mapM (print_pattern 0) ps >>= fun ps' ->
                     return @@ paren @@ print_tupled ps'
  | Tpat_construct (_, desc, ps) -> print_construct prec print_pattern desc ps
  | _ -> Bad "Some pattern syntax not implemented"

(* Pattern can be matched on LHS; no need for case expression *)
let case_is_trivial c =
  match c.c_lhs.pat_desc, c.c_guard with
  | (Tpat_any | Tpat_var _), None -> true
  | _ -> false

let rec print_expression casesfollow prec expr =
  match expr.exp_desc with
  | Texp_ident (path, _, desc) -> print_path path
  | Texp_constant c ->  return @@ print_constant c
  | Texp_let (r, bs, e) ->
    mapiM (fun i -> print_value_binding (i = 0) r) bs >>= fun bs' ->
    print_expression false 0 e >>= fun e' ->
    return @@ ifThen (prec > 1) paren @@ Box (Hv, 0, [
      Box (Hv, indent, [Lit "let"; sp; Box (V, 0, intersperse sp bs')]); sp;
      Box (Hv, indent, [Lit "in"; sp; e']); sp;
      Lit "end"
    ])
  | Texp_function (l, [c], p) ->
    print_case false c >>= fun c' ->
    return @@ ifThen (prec > 1) paren @@ Box (Hovp, indent, [Lit "fn "] @
      if case_is_trivial c then
        (* fn x => E *)
        [c']
      else
        (* fn tmp__ => case tmp__ of P => E *)
        [Lit "tmp__"; sp; Lit "=>"; sp; Box (Hovs, indent, [
          Lit "case"; sp; Lit "tmp__"; sp; Lit "of"; sp; c'
        ])]
    )
  (* fn tmp__ => case tmp__ of P0 => E0 | P1 => E1 | ... *)
  | Texp_function (l, cs, p) ->
    print_case_cases cs >>= fun cs' ->
    return @@ ifThen (prec > 1 || casesfollow) paren @@ Box (Hovp, indent, [
      Lit "fn "; Box (Hovs, indent, [
        Lit "tmp__"; sp; Lit "=>"; sp;
        Box (Hv, indent, [
          Box (Hovp, 0, [Lit "case"; sp; Lit "tmp__"; sp; Lit "of"]); sp; cs'
        ])
      ])
    ])
  (* Special cases *)
  | Texp_apply ({ exp_desc = Texp_ident (Pdot (Pident m, n, _), _, _) },
                [_, Some e0, _; _, Some e1, _])
      when m.name = "Pervasives" && BatList.mem n ["&&"; "&"; "||"; "or"] ->
    let op = match n with
      | "&&" | "&" -> "andalso"
      | "||" | "or" -> "orelse"
      | x -> x
    in
    print_expression false 2 e0 >>= fun e0' ->
    print_expression casesfollow 2 e1 >>= fun e1' ->
    return @@ Box (Hovp, indent, [e0'; sp; Lit op; sp; e1'])
  (* Normal function application *)
  | Texp_apply (e0, es) ->
    print_expression false 2 e0 >>= fun e0' ->
    mapM (function
      | l, Some e, Required -> print_expression casesfollow 2 e
      | _ -> Bad "Optional and named arguments not supported."
    ) es >>= fun es' ->
    return @@ ifThen (prec > 1) paren @@
      Box (Hv, indent, intersperse sp (e0' :: es'))
  | Texp_match (exp, cs, [], p) ->
    print_expression false 0 exp >>= fun exp' ->
    print_case_cases cs >>= fun cs' ->
    return @@ ifThen (prec > 0 || casesfollow) paren @@ Box (Hovs, indent, [
      Box (Hovp, 2 * indent, [Lit "case"; sp; exp'; sp; Lit "of"]); sp; cs'
    ])
  | Texp_try (exp, cs) ->
    print_expression false 1 exp >>= fun exp' ->
    print_case_cases cs >>= fun cs' ->
    return @@ ifThen (prec > 0) paren @@ Box (Hovp, indent, [
      exp'; sp; Lit "handle"; sp; cs'
    ])
  | Texp_tuple es -> mapM (print_expression false 0) es <&> print_tupled
  | Texp_construct (_, desc, es) ->
    print_construct prec (print_expression casesfollow) desc es
  | Texp_ifthenelse (p, et, Some ef) ->
    print_expression false 0 p >>= fun p' ->
    print_expression false 0 et >>= fun et' ->
    print_expression casesfollow prec ef >>= fun ef' ->
    return @@ ifThen (prec > 0) paren @@ Box (Hovs, 0, [
      Box (Hovp, indent, [Lit "if"; sp; p'; sp; Lit "then"; sp; et']);
      sp; Box (Hovp, indent, [Lit "else"; sp; ef'])
    ])
  (* E0; E1 *)
  | Texp_sequence (e0, e1) ->
    print_expression false 0 e0 >>= fun e0' ->
    print_expression casesfollow 0 e1 >>= fun e1' ->
    return @@ paren @@ Box (Hovs, 0, [e0'; Lit ";"; sp; e1'])
  | _ -> Bad "Some expression syntax not implemented."

and print_case casesfollow c =
  print_pattern 0 c.c_lhs >>= fun pat ->
  print_expression casesfollow 1 c.c_rhs >>= fun exp ->
  match c.c_guard with
  | None -> return @@ Box (Hovp, indent, [pat; sp; Lit "=>"; sp; exp])
  | _ -> Bad "Pattern guards not supported."

and print_case_cases cs =
  mapM (print_case true) cs <&> (function
    | [] -> []
    | c' :: cs' ->
      Box (H, 0, [Lit "  "; c']) ::
        BatList.map (fun c -> Box (H, 0, [Lit "| "; c])) cs')
  <&> fun cs' ->
  Box (Hv, 0, intersperse sp cs')

and print_value_binding first_binding rec_flag vb =
  let keyword = match first_binding, rec_flag with
                | _, Nonrecursive -> "val"
                | true, Recursive -> "fun"
                | false, Recursive -> "and"
  in
  print_pattern 0 vb.vb_pat >>= fun name ->
  match vb.vb_expr.exp_desc, rec_flag with
  (* Special case for trivial patterns *)
  | Texp_function (l, [c], p), Recursive when case_is_trivial c ->
    (* Try to turn `fun f x = fn y => fn z => ...` into `fun f x y z = ...` *)
    let rec reduce_fn acc lastc =
      match lastc.c_rhs.exp_desc with
      | Texp_function (_, [nextc], _) when case_is_trivial nextc ->
        reduce_fn (lastc.c_lhs :: acc) nextc
      | _ ->
        mapM (print_pattern 0) (BatList.rev acc) >>= fun vs ->
        print_pattern 2 lastc.c_lhs >>= fun pat ->
        print_expression false 0 lastc.c_rhs >>= fun exp ->
        return @@ Box (Hovp, indent,
          [Lit keyword; sp; name] @
          BatList.concat (BatList.map (fun x -> [sp; x]) vs) @
          [sp; pat; sp; Lit "="; sp; exp]
        )
    in
    reduce_fn [] c
  (* fun tmp__ = case tmp__ of P0 => E0 | ... *)
  | Texp_function (l, cs, p), Recursive ->
    print_case_cases cs >>= fun cs' ->
    return @@ Box (Hovp, indent, [
      Lit keyword; sp; name; sp; Lit "tmp__"; sp; Lit "="; sp;
      Box (Hovp, 2 * indent, [Lit "case"; sp; Lit "tmp__"; sp; Lit "of"]);
      sp; cs'
    ])
  (* Should have been removed by the AST preprocessor *)
  | _, Recursive -> Bad "Recursive values not supported in CakeML."
  (* val x = E *)
  | _, Nonrecursive ->
    print_expression false 0 vb.vb_expr >>= fun expr ->
    return @@ Box (Hovp, indent, [
      Lit keyword; sp; name; sp; Lit "="; sp; expr
    ])

let rec print_core_type prec ctyp =
  let thisParen = ifThen (prec > 1) paren in
  match ctyp.ctyp_desc with
  | Ttyp_any -> return @@ Lit "_"
  | Ttyp_var name -> return @@ Lit ("'" ^ fix_type_name name)
  | Ttyp_arrow ("", dom, cod) ->
    print_core_type 2 dom >>= fun a ->
    print_core_type 1 cod >>= fun b ->
    return @@ thisParen @@ Box (Hovp, indent, [a; sp; Lit "->"; sp; b])
  | Ttyp_tuple ts -> print_ttyp_tuple ts >>= fun t ->
                     return @@ paren t
  | Ttyp_constr (path, _, ts) ->
    print_path path >>= fun name ->
    print_typ_params ts >>= fun params ->
    return @@ Box (Hovp, indent, [params; sp; name])
  | Ttyp_poly (_, t) -> print_core_type prec t
  | _ -> Bad "Some core types syntax not supported."

and print_typ_params = function
  | [] -> return @@ Lit ""
  | [t] -> print_core_type 2 t
  | ts -> mapM (print_core_type 0) ts <&> print_tupled

and print_ttyp_tuple ts =
  mapM (print_core_type 0) ts >>= fun ts' ->
  return @@ Box (Hovp, indent, intersperseMany [sp; Lit "*"; sp] ts')

let print_constructor_arguments = print_ttyp_tuple

let print_constructor_declaration decl =
  print_constructor_arguments decl.cd_args >>= fun constructor_args ->
  return @@ Box (Hovp, indent, [Lit decl.cd_name.txt] @
    if constructor_args = Lit ""
      then []
      else [sp; Lit "of"; sp; constructor_args]
  )

let print_ttyp_variant ds =
  (mapM (print_constructor_declaration) ds <&> function
    | [] -> []
    | d' :: ds' ->
      Box (H, 0, [Lit "  "; sp; d']) ::
        BatList.map (fun d -> Box (H, 0, [Lit " |"; sp; d])) ds')
  >>= fun ds' ->
  return @@ Box (Hv, 0, ds')

let print_type_declaration first_binding typ =
  let keyword = match first_binding, typ.typ_kind with
                | false, _ -> "and"
                | true, Ttype_abstract -> "type"
                | true, _ -> "datatype"
  in
  print_typ_params (BatList.map Tuple2.first typ.typ_params) >>= fun params ->
  (match typ.typ_manifest, typ.typ_kind with
  (* type t' = t *)
  | Some m, Ttype_abstract ->
    print_core_type 0 m >>= fun manifest ->
    return [Lit "="; sp; manifest]
  (* datatype t' = datatype t *)
  | Some m, Ttype_variant ds ->
    print_core_type 0 m >>= fun manifest ->
    return [Lit "="; sp; Lit "datatype"; sp; manifest]
  (* type t *)
  | None, Ttype_abstract -> return []
  (* datatype t = A | B | ... *)
  | None, Ttype_variant ds ->
    print_ttyp_variant ds >>= fun expr ->
    return [Lit "="; sp; expr]
  | _ -> Bad "Some type declarations not supported."
  ) >>= fun rest ->
  return @@ Box (Hovp, indent, [
    Lit keyword; sp; params; Lit (fix_type_name typ.typ_name.txt); sp
  ] @ rest)

let rec print_module_expr expr =
  match expr.mod_desc with
  | Tmod_structure str ->
    let str_items =
      BatList.concat (BatList.map preprocess_valrec_str_item str.str_items) in
    print_str_items str_items >>= fun items ->
    return @@ Box (Hovs, indent, [Lit "struct"; sp; items;
      Break (1, -indent); Lit "end"])
  | _ -> Bad "Some module types not supported."

and print_module_binding mb =
  print_module_expr mb.mb_expr >>= fun expr ->
  let name = mb.mb_id.name in
  match mb.mb_expr.mod_desc with
  | Tmod_structure str ->
    return @@ Box (Hovp, indent, [
      Lit "structure"; sp; Lit name; sp; Lit "="; sp; expr
    ])
  | _ -> Bad "Some module types not supported."

and print_structure_item str =
  match str.str_desc with
  | Tstr_eval (e, attrs) ->
    print_expression false 0 e >>= fun e' ->
    return @@ Box (Hovp, indent, [
      Lit "val"; sp; Lit "eval__"; sp; Lit "="; sp; e'
    ])
  | Tstr_value (r, bs) ->
    mapiM (fun i -> print_value_binding (i = 0) r) bs >>= fun bs' ->
    return @@ Box (Hovs, 0, bs')
  | Tstr_type ds ->
    mapiM (fun i -> print_type_declaration (i = 0)) ds >>= fun ds' ->
    return @@ Box (Hovs, 0, ds')
  | Tstr_exception constructor ->
    (match constructor.ext_kind with
    | Text_decl ([], None) -> return @@ Lit ""
    | Text_decl (ts, None) ->
      print_constructor_arguments ts >>= fun ts' ->
      return @@ Box (Hovp, indent, [Lit "of"; sp; ts'])
    | Text_rebind (path, _) ->
      print_path path >>= fun p ->
      return @@ Box (Hovp, indent, [Lit "="; sp; p])
    | _ -> Bad "Some exception declaration syntax not supported."
    ) >>= fun rest ->
    return @@ Box (Hovp, indent, [
      Lit "exception"; sp; Lit constructor.ext_name.txt; sp; rest
    ])
  | Tstr_module b -> print_module_binding b
  (* Things are annotated with full module paths, making `open` unnecessary. *)
  | Tstr_open _ -> return @@ Lit ""
  | _ -> Bad "Some structure items not supported."

and print_str_items ss =
  mapM print_structure_item ss <&>
  BatList.filter (fun x -> Lit "" <> x)
  %> BatList.map (fun x -> Box (H, 0, [x; Lit ";"]))
  %> fun xs -> Box (V, 0, intersperseMany [Newline; Newline] xs)
  (*return @@ Box (V, 0, ss')*)

let output_result = function
  | Ok r -> interp r
  | Bad e -> print_endline @@ "Error: " ^ e; exit 1

(*let concat_items =
  BatList.filter (fun x -> Lit "" <> x)
  %> BatList.map (fun x -> Box (H, 0, [x; Lit ";"]))
  %> fun xs -> Box (V, 0, intersperseMany [Newline; Newline] xs)*)

let lexbuf = Lexing.from_channel stdin
let parsetree = Parse.implementation lexbuf
let _ = Compmisc.init_path false
let typedtree, signature, env =
  Typemod.type_structure (Compmisc.initial_env ()) parsetree Location.none
let str = RecordMap.map_structure (MatchMap.map_structure typedtree)
let str_items =
  BatList.concat (BatList.map preprocess_valrec_str_item str.str_items)
let _ = output_result (print_str_items str_items)
(*let () = Printtyped.implementation Format.std_formatter
  { typedtree with str_items; }*)