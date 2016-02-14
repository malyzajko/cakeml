open preamble
     stack_allocTheory
     stackSemTheory
     stackPropsTheory
     bvp_to_wordProofTheory

val _ = new_theory"stack_allocProof";

val good_syntax_def = Define `
  (good_syntax (Alloc v) <=> (v = 1)) /\
  (good_syntax ((Seq p1 p2):'a stackLang$prog) <=>
     good_syntax p1 /\ good_syntax p2) /\
  (good_syntax ((If c r ri p1 p2):'a stackLang$prog) <=>
     good_syntax p1 /\ good_syntax p2) /\
  (good_syntax (While c r ri p1) <=>
     good_syntax p1) /\
  (good_syntax (Call x1 _ x2) <=>
     (case x1 of | SOME (y,r,_,_) => good_syntax y | NONE => T) /\
     (case x2 of SOME (y,_,_) => good_syntax y | NONE => T)) /\
  (good_syntax _ <=> T)`

val get_var_imm_case = prove(
  ``get_var_imm ri s =
    case ri of
    | Reg n => get_var n s
    | Imm w => SOME (Word w)``,
  Cases_on `ri` \\ fs [get_var_imm_def]);

val prog_comp_lemma = prove(
  ``prog_comp = \(n,p). (n,FST (comp n (next_lab p) p))``,
  fs [FUN_EQ_THM,FORALL_PROD,prog_comp_def]);

val lookup_IMP_lookup_compile = prove(
  ``lookup dest s.code = SOME x /\ 30 <= dest ==>
    ?m1 n1. lookup dest (fromAList (compile c (toAList s.code))) =
            SOME (FST (comp m1 n1 x))``,
  fs [lookup_fromAList,compile_def] \\ rw [ALOOKUP_APPEND]
  \\ `ALOOKUP (stubs c) dest = NONE` by
    (fs [stubs_def] \\ rw [] \\ fs [] \\ decide_tac) \\ fs []
  \\ fs [prog_comp_lemma] \\ fs [ALOOKUP_MAP_gen,ALOOKUP_toAList]
  \\ metis_tac []);

val word_gc_fun_lemma = word_gc_fun_def
  |> SIMP_RULE std_ss [word_full_gc_def]
  |> SIMP_RULE std_ss [Once LET_THM]
  |> SIMP_RULE std_ss [Once LET_THM]
  |> SIMP_RULE std_ss [Once LET_THM]
  |> SIMP_RULE std_ss [Once LET_THM]
  |> SIMP_RULE std_ss [Once LET_THM,word_gc_move_roots_def]

val word_gc_fun_thm = prove(
  ``word_gc_fun conf (roots,m,dm,s) =
      let (w1,i1,pa1,m1,c1) =
            word_gc_move conf
              (s ' Globals,0w,theWord (s ' OtherHeap),
               theWord (s ' CurrHeap),m,dm) in
      let (ws2,i2,pa2,m2,c2) =
            word_gc_move_roots conf
              (roots,i1,pa1,theWord (s ' CurrHeap),m1,dm) in
      let (i1,pa1,m1,c2) =
            word_gc_move_loop conf
              (theWord (s ' OtherHeap),i2,pa2,
               theWord (s ' CurrHeap),m2,dm,c1 /\ c2) in
      let s1 =
            s |++
            [(CurrHeap,Word (theWord (s ' OtherHeap)));
             (OtherHeap,Word (theWord (s ' CurrHeap)));
             (NextFree,Word pa1);
             (EndOfHeap,
              Word
                (theWord (s ' OtherHeap) +
                 theWord (s ' HeapLength))); (Globals,w1)]
      in
        if c2 then SOME (ws2,m1,s1) else NONE``,
  fs [word_gc_fun_lemma,LET_THM]
  \\ rpt (split_pair_tac \\ fs [] \\ rpt var_eq_tac \\ fs [])
  \\ IF_CASES_TAC \\ fs []);

val gc_lemma = gc_def
  |> SPEC_ALL
  |> DISCH ``s.gc_fun = word_gc_fun conf``
  |> SIMP_RULE std_ss [] |> UNDISCH
  |> SIMP_RULE std_ss [word_gc_fun_thm] |> DISCH_ALL

val word_gc_move_roots_bitmaps_def = Define `
  word_gc_move_roots_bitmaps conf (stack,bitmaps,i1,pa1,curr,m,dm) =
    case enc_stack bitmaps stack of
    | NONE => (ARB,ARB,ARB,ARB,F)
    | SOME wl_list =>
        let (wl,i2,pa2,m2,c2) =
            word_gc_move_roots conf (wl_list,i1,pa1,curr,m,dm) in
          case dec_stack bitmaps wl stack of
          | NONE => (ARB,ARB,ARB,ARB,F)
          | SOME stack => (stack,i2,pa2,m2,c2)`

val word_gc_move_loop_ok = store_thm("word_gc_move_loop_ok",
  ``word_gc_move_loop conf (pb,i,pa,old,m,dm,F) = (i1,pa1,m1,c1) ==> ~c1``,
  cheat);

val gc_thm = prove(
  ``s.gc_fun = word_gc_fun conf ⇒
   gc s =
   if LENGTH s.stack < s.stack_space then NONE else
     let unused = TAKE s.stack_space s.stack in
     let stack = DROP s.stack_space s.stack in
     let (w1,i1,pa1,m1,c1) =
              word_gc_move conf
                (s.store ' Globals,0w,
                 theWord (s.store ' OtherHeap),
                 theWord (s.store ' CurrHeap),s.memory,s.mdomain) in
     let (stack,i2,pa2,m2,c2) =
           word_gc_move_roots_bitmaps conf
             (stack,s.bitmaps,i1,pa1,
              theWord (s.store ' CurrHeap),m1,s.mdomain) in
     let (i1,pa1,m1,c2) =
           word_gc_move_loop conf
             (theWord (s.store ' OtherHeap),i2,pa2,
              theWord (s.store ' CurrHeap),m2,s.mdomain,
              c1 ∧ c2) in
     let s1 =
           s.store |++
           [(CurrHeap,Word (theWord (s.store ' OtherHeap)));
            (OtherHeap,Word (theWord (s.store ' CurrHeap)));
            (NextFree,Word pa1);
            (EndOfHeap,
             Word
               (theWord (s.store ' OtherHeap) +
                theWord (s.store ' HeapLength)));
            (Globals,w1)] in
       if c2 then SOME (s with
                       <|stack := unused ++ stack; store := s1;
                         regs := FEMPTY; memory := m1|>) else NONE``,
  strip_tac \\ drule gc_lemma
  \\ disch_then (fn th => fs [th])
  \\ IF_CASES_TAC \\ fs []
  \\ fs [LET_THM,word_gc_move_roots_bitmaps_def]
  \\ CASE_TAC \\ fs []
  THEN1
   (rpt (split_pair_tac \\ fs [] \\ rpt var_eq_tac \\ fs [])
    \\ imp_res_tac word_gc_move_loop_ok)
  \\ rpt (split_pair_tac \\ fs [] \\ rpt var_eq_tac \\ fs [])
  \\ Cases_on `dec_stack s.bitmaps ws2 (DROP s.stack_space s.stack)`
  THEN1
   (fs [] \\ rpt var_eq_tac \\ fs []
    \\ imp_res_tac word_gc_move_loop_ok \\ fs []
    \\ IF_CASES_TAC \\ fs [])
  \\ fs [] \\ rpt var_eq_tac \\ fs []
  \\ IF_CASES_TAC \\ fs []);

val word_gc_move_bitmaps_def = Define `
  word_gc_move_bitmaps conf (w,stack,bitmaps,i1,pa1,curr,m,dm) =
    case full_read_bitmap bitmaps w of
    | NONE => NONE
    | SOME bs =>
      case filter_bitmap bs stack of
      | NONE => NONE
      | SOME (ts,ws) =>
        let (wl,i2,pa2,m2,c2) =
                word_gc_move_roots conf (ts,i1,pa1,curr,m,dm) in
          case map_bitmap bs wl stack of
          | NONE => NONE
          | SOME (hd,ts1,ws') =>
              SOME (hd,ws,i2,pa2,m2,c2)`

val word_gc_move_roots_APPEND = prove(
  ``!xs ys i1 pa1 m.
      word_gc_move_roots conf (xs++ys,i1,pa1,curr,m,dm) =
        let (ws1,i1,pa1,m1,c1) = word_gc_move_roots conf (xs,i1,pa1,curr,m,dm) in
        let (ws2,i2,pa2,m2,c2) = word_gc_move_roots conf (ys,i1,pa1,curr,m1,dm) in
          (ws1++ws2,i2,pa2,m2,c1 /\ c2)``,
  Induct \\ fs [word_gc_move_roots_def,LET_THM]
  \\ rw [] \\ split_pair_tac \\ fs []
  \\ Cases_on `word_gc_move conf (h,i1,pa1,curr,m,dm)` \\ PairCases_on `r` \\ fs []
  \\ Cases_on `word_gc_move_roots conf (xs,r0,r1,curr,r2,dm)`
  \\ PairCases_on `r` \\ fs []
  \\ Cases_on `word_gc_move_roots conf (ys,r0',r1',curr,r2',dm)`
  \\ PairCases_on `r` \\ fs []
  \\ EQ_TAC \\ fs []);

val map_bitmap_APPEND = prove(
  ``!x q stack p0 p1.
      filter_bitmap x stack = SOME (p0,p1) /\
      LENGTH q = LENGTH p0 ==>
      map_bitmap x (q ++ q') stack =
      case map_bitmap x q stack of
      | NONE => NONE
      | SOME (hd,ts,ws) => SOME (hd,ts++q',ws)``,
  Induct \\ fs [map_bitmap_def]
  \\ reverse (Cases \\ Cases_on `stack`)
  \\ fs [map_bitmap_def,filter_bitmap_def]
  THEN1 (rw [] \\ rpt (CASE_TAC \\ fs []))
  \\ CASE_TAC \\ fs []
  \\ CASE_TAC \\ fs []
  \\ Cases \\ fs [map_bitmap_def]
  \\ every_case_tac \\ fs []);

val word_gc_move_roots_IMP_LENGTH = store_thm("word_gc_move_roots_IMP_LENGTH",
  ``!xs r0 r1 curr r2 dm ys i2 pa2 m2 c conf.
      word_gc_move_roots conf (xs,r0,r1,curr,r2,dm) = (ys,i2,pa2,m2,c) ==>
      LENGTH ys = LENGTH xs``,
  Induct \\ fs [word_gc_move_roots_def,LET_THM] \\ rw []
  \\ rpt (split_pair_tac \\ fs []) \\ rpt var_eq_tac \\ fs []
  \\ res_tac);

val filter_bitmap_map_bitmap = store_thm("filter_bitmap_map_bitmap",
  ``!x t q xs xs1 z ys ys1.
      filter_bitmap x t = SOME (xs,xs1) /\
      LENGTH q = LENGTH xs /\
      map_bitmap x q t = SOME (ys,z,ys1) ==>
      z = [] /\ ys1 = xs1``,
  Induct
  THEN1 (Cases_on `q` \\ Cases_on `t` \\ fs [filter_bitmap_def,map_bitmap_def])
  \\ Cases_on `t` \\ Cases_on `q` \\ Cases
  \\ rewrite_tac [filter_bitmap_def] \\ simp_tac std_ss [map_bitmap_def]
  THEN1
   (Cases_on `xs` \\ simp_tac std_ss [map_bitmap_def,LENGTH,ADD1]
    \\ CASE_TAC \\ qcase_tac `_ = SOME y` \\ PairCases_on `y`
    \\ simp_tac (srw_ss()) [map_bitmap_def,LENGTH,ADD1]
    \\ ntac 2 strip_tac \\ first_x_assum drule
    \\ disch_then (qspec_then `[]` mp_tac) \\ fs [])
  THEN1
   (CASE_TAC \\ qcase_tac `_ = SOME y` \\ PairCases_on `y`
    \\ simp_tac (srw_ss()) [map_bitmap_def,LENGTH,ADD1]
    \\ CASE_TAC \\ qcase_tac `_ = SOME y` \\ PairCases_on `y`
    \\ simp_tac (srw_ss()) [map_bitmap_def,LENGTH,ADD1]
    \\ metis_tac [])
  \\ CASE_TAC \\ qcase_tac `_ = SOME y` \\ PairCases_on `y`
  \\ simp_tac (srw_ss()) []
  \\ rpt gen_tac \\ strip_tac
  \\ first_x_assum match_mp_tac
  \\ qexists_tac `t'` \\ fs []
  \\ qexists_tac `h'::t` \\ fs []);

val word_gc_move_roots_bitmaps = prove(
  ``!stack i1 pa1 m stack2 i2 pa2 m2.
      (word_gc_move_roots_bitmaps conf (stack,bitmaps,i1,pa1,curr,m,dm) =
        (stack2,i2,pa2,m2,T)) ==>
      word_gc_move_roots_bitmaps conf (stack,bitmaps,i1,pa1,curr,m,dm) =
      case stack of
      | [] => (ARB,ARB,ARB,ARB,F)
      | (w::ws) =>
        if w = Word 0w then (stack,i1,pa1,m,ws = []) else
          case word_gc_move_bitmaps conf (w,ws,bitmaps,i1,pa1,curr,m,dm) of
          | NONE => (ARB,ARB,ARB,ARB,F)
          | SOME (new,stack,i2,pa2,m2,c2) =>
              let (stack,i,pa,m,c2) =
                word_gc_move_roots_bitmaps conf (stack,bitmaps,i2,pa2,curr,m2,dm) in
                  (w::new++stack,i,pa,m,c2)``,
  Cases THEN1 (fs [word_gc_move_roots_bitmaps_def,enc_stack_def])
  \\ rpt strip_tac \\ pop_assum mp_tac \\ fs []
  \\ IF_CASES_TAC \\ fs []
  THEN1 (fs [word_gc_move_roots_bitmaps_def,enc_stack_def]
         \\ IF_CASES_TAC \\ fs [word_gc_move_roots_def,LET_THM,dec_stack_def])
  \\ fs [word_gc_move_roots_bitmaps_def,word_gc_move_bitmaps_def,enc_stack_def]
  \\ Cases_on `full_read_bitmap bitmaps h` \\ fs []
  \\ Cases_on `filter_bitmap x t` \\ fs []
  \\ qcase_tac `_ = SOME filter_res` \\ PairCases_on `filter_res` \\ fs []
  \\ Cases_on `enc_stack bitmaps filter_res1` \\ fs []
  \\ qcase_tac `_ = SOME enc_rest` \\ fs [word_gc_move_roots_APPEND]
  \\ simp [Once LET_DEF]
  \\ Cases_on `word_gc_move_roots conf (filter_res0,i1,pa1,curr,m,dm)` \\ fs []
  \\ PairCases_on `r` \\ fs [dec_stack_def]
  \\ Cases_on `word_gc_move_roots conf (enc_rest,r0,r1,curr,r2,dm)` \\ fs []
  \\ PairCases_on `r` \\ fs []
  \\ CASE_TAC \\ fs [] \\ qcase_tac `_ = SOME map_rest` \\ fs []
  \\ PairCases_on `map_rest` \\ fs []
  \\ imp_res_tac word_gc_move_roots_IMP_LENGTH \\ fs []
  \\ drule (GEN_ALL map_bitmap_APPEND) \\ fs []
  \\ disch_then (mp_tac o SPEC_ALL) \\ fs []
  \\ fs [] \\ pop_assum kall_tac
  \\ CASE_TAC \\ fs []
  \\ qcase_tac `_ = SOME z` \\ fs [] \\ PairCases_on `z` \\ fs []
  \\ strip_tac \\ rpt var_eq_tac \\ fs []
  \\ CASE_TAC \\ fs []
  \\ strip_tac \\ rpt var_eq_tac \\ fs []
  \\ imp_res_tac word_gc_move_roots_IMP_LENGTH \\ fs []
  \\ drule filter_bitmap_map_bitmap
  \\ disch_then drule \\ fs []
  \\ strip_tac \\ rpt var_eq_tac \\ fs []);

val get_bits_def = Define `
  get_bits w = GENLIST (\i. w ' i) (bit_length w − 1)`

val word_gc_move_bitmap_def = Define `
  word_gc_move_bitmap conf (w,stack,i1,pa1,curr,m,dm) =
    let bs = get_bits w in
      case filter_bitmap bs stack of
      | NONE => NONE
      | SOME (ts,ws) =>
         let (wl,i2,pa2,m2,c2) = word_gc_move_roots conf (ts,i1,pa1,curr,m,dm) in
           case map_bitmap bs wl stack of
           | NONE => NONE
           | SOME (hd,v2) => SOME (hd,ws,i2,pa2,m2,c2)`

val bit_length_thm = store_thm("bit_length_thm",
  ``!w. ((w >>> bit_length w) = 0w) /\ !n. n < bit_length w ==> (w >>> n) <> 0w``,
  HO_MATCH_MP_TAC bit_length_ind \\ rw []
  \\ once_rewrite_tac [bit_length_def]
  \\ rw [] \\ fs [AC ADD_COMM ADD_ASSOC]
  \\ Cases_on `w = 0w` \\ fs [EVAL ``bit_length 0w``]
  \\ Cases_on `n` \\ fs []
  \\ ntac 2 (pop_assum mp_tac)
  \\ once_rewrite_tac [bit_length_def]
  \\ fs [ADD1] \\ rw []);

val word_lsr_dimindex = prove(
  ``(w:'a word) >>> dimindex (:'a) = 0w``,
  fs []);

val bit_length_LESS_EQ_dimindex = store_thm("bit_length_LESS_EQ_dimindex",
  ``bit_length (w:'a word) <= dimindex (:'a)``,
  CCONTR_TAC \\ fs [GSYM NOT_LESS] \\ imp_res_tac bit_length_thm
  \\ fs [word_lsr_dimindex]);

val shift_to_zero_word_msb = store_thm("shift_to_zero_word_msb",
  ``(w:'a word) >>> n = 0w /\ word_msb w ==> dimindex (:'a) <= n``,
  fs [fcpTheory.CART_EQ,word_0,word_lsr_def,fcpTheory.FCP_BETA,word_msb_def]
  \\ rw [] \\ CCONTR_TAC \\ fs [] \\ fs [GSYM NOT_LESS]
  \\ qpat_assum `!xx.bb` mp_tac \\ fs []
  \\ qexists_tac `dimindex (:α) - 1 - n`
  \\ `dimindex (:α) - 1 - n + n = dimindex (:α) - 1` by decide_tac \\ fs []
  \\ decide_tac);

val word_msb_IMP_bit_length = prove(
  ``!h. word_msb (h:'a word) ==> (bit_length h = dimindex (:'a))``,
  rw [] \\ imp_res_tac shift_to_zero_word_msb \\ CCONTR_TAC
  \\ imp_res_tac (DECIDE ``n<>m ==> n < m \/ m < n:num``)
  \\ qspec_then `h` mp_tac bit_length_thm
  \\ strip_tac \\ res_tac \\ fs [word_lsr_dimindex] \\ decide_tac);

val get_bits_intro = prove(
  ``word_msb (h:'a word) ==>
    GENLIST (\i. h ' i) (dimindex (:'a) - 1) = get_bits h``,
  fs [get_bits_def,word_msb_IMP_bit_length]);

val DROP_IMP_LESS_LENGTH = prove(
  ``!xs n y ys. DROP n xs = y::ys ==> n < LENGTH xs``,
  Induct \\ fs [DROP_def] \\ rw [] \\ res_tac \\ decide_tac);

val DROP_EQ_CONS_IMP_DROP_SUC = prove(
  ``!xs n y ys. DROP n xs = y::ys ==> DROP (SUC n) xs = ys``,
  Induct \\ fs [DROP_def] \\ rw [] \\ res_tac \\ fs [ADD1]
  \\ `n - 1 + 1 = n` by decide_tac \\ fs []);

val filter_bitmap_APPEND = prove(
  ``!xs stack ys.
      filter_bitmap (xs ++ ys) stack =
      case filter_bitmap xs stack of
      | NONE => NONE
      | SOME (zs,rs) =>
        case filter_bitmap ys rs of
        | NONE => NONE
        | SOME (zs2,rs) => SOME (zs ++ zs2,rs)``,
  Induct \\ Cases_on `stack` \\ fs [filter_bitmap_def]
  THEN1 (rw [] \\ every_case_tac \\ fs [])
  THEN1 (rw [] \\ every_case_tac \\ fs [])
  \\ Cases \\ fs [filter_bitmap_def] \\ rw [] \\ rpt (CASE_TAC \\ fs []));

val map_bitmap_APPEND_APPEND = prove(
  ``!vs1 stack x0 x1 ws2 vs2 ws1.
      filter_bitmap vs1 stack = SOME (x0,x1) /\
      LENGTH x0 = LENGTH ws1 ==>
      map_bitmap (vs1 ++ vs2) (ws1 ++ ws2) stack =
      case map_bitmap vs1 ws1 stack of
      | NONE => NONE
      | SOME (ts1,ts2,ts3) =>
        case map_bitmap vs2 ws2 ts3 of
        | NONE => NONE
        | SOME (us1,us2,us3) => SOME (ts1++us1,ts2++us2,us3)``,
  Induct \\ fs [map_bitmap_def] THEN1
   (Cases \\ fs [filter_bitmap_def]
    \\ once_rewrite_tac [EQ_SYM_EQ] \\ fs [LENGTH_NIL]
    \\ rw [] \\ every_case_tac \\ fs [])
  \\ Cases_on `stack` \\ fs [filter_bitmap_def]
  \\ reverse Cases \\ fs [filter_bitmap_def,map_bitmap_def]
  THEN1 (rw [] \\ every_case_tac \\ fs [])
  \\ CASE_TAC \\ fs []
  \\ CASE_TAC \\ fs []
  \\ Cases_on `ws1` \\ fs [LENGTH,map_bitmap_def]
  \\ rw [] \\ every_case_tac \\ fs []) |> SIMP_RULE std_ss [];

val word_gc_move_bitmaps_unroll = prove(
  ``LENGTH bitmaps < dimword (:'a) - 1 /\ good_dimindex (:'a) /\
    word_gc_move_bitmaps conf (Word w,stack,bitmaps,i1,pa1,curr,m,dm) = SOME x ==>
    word_gc_move_bitmaps conf (Word w,stack,bitmaps,i1,pa1,curr,m,dm) =
    case DROP (w2n (w - 1w:'a word)) bitmaps of
    | [] => NONE
    | (y::ys) =>
      case word_gc_move_bitmap conf (y,stack,i1,pa1,curr,m,dm) of
      | NONE => NONE
      | SOME (hd,ws,i2,pa2,m2,c2) =>
          if ~(word_msb y) then SOME (hd,ws,i2,pa2,m2,c2) else
            case word_gc_move_bitmaps conf (Word (w+1w),ws,bitmaps,i2,pa2,curr,m2,dm) of
            | NONE => NONE
            | SOME (hd3,ws3,i3,pa3,m3,c3) =>
                SOME (hd++hd3,ws3,i3,pa3,m3,c2 /\ c3)``,
  fs [word_gc_move_bitmaps_def,full_read_bitmap_def]
  \\ Cases_on `w = 0w` \\ fs []
  \\ Cases_on `DROP (w2n (w + -1w)) bitmaps` \\ fs [read_bitmap_def]
  \\ reverse (Cases_on `word_msb h`)
  THEN1
   (fs [word_gc_move_bitmap_def,get_bits_def,LET_THM]
    \\ CASE_TAC \\ qcase_tac `_ = SOME y` \\ PairCases_on `y` \\ fs []
    \\ split_pair_tac \\ fs []
    \\ CASE_TAC \\ qcase_tac `_ = SOME y` \\ PairCases_on `y` \\ fs []
    \\ strip_tac \\ rpt var_eq_tac \\ fs [])
  \\ fs [] \\ Cases_on `read_bitmap t` \\ fs []
  \\ CASE_TAC \\ qcase_tac `_ = SOME y` \\ PairCases_on `y` \\ fs [LET_THM]
  \\ split_pair_tac \\ fs []
  \\ CASE_TAC \\ qcase_tac `_ = SOME z` \\ PairCases_on `z` \\ fs [LET_THM]
  \\ fs [word_gc_move_bitmap_def,LET_THM] \\ rfs [get_bits_intro]
  \\ strip_tac \\ rpt var_eq_tac
  \\ IF_CASES_TAC THEN1
   (`F` by all_tac
    \\ fs [wordsLib.WORD_DECIDE ``w+1w=0w <=> (w = -1w)``]
    \\ rpt var_eq_tac \\ fs [labPropsTheory.good_dimindex_def]
    \\ fs [word_2comp_def] \\ fs [dimword_def]
    \\ imp_res_tac DROP_IMP_LESS_LENGTH \\ decide_tac)
  \\ `DROP (w2n w) bitmaps = t` by
   (`w2n w = SUC (w2n (w + -1w))` suffices_by
      metis_tac [DROP_EQ_CONS_IMP_DROP_SUC]
    \\ Cases_on `w` \\ fs [word_add_n2w]
    \\ `~(n < 1) /\ n - 1 < dimword (:'a)` by decide_tac
    \\ full_simp_tac std_ss [GSYM word_sub_def,addressTheory.word_arith_lemma2]
    \\ fs [] \\ decide_tac) \\ fs [] \\ pop_assum kall_tac
  \\ fs [filter_bitmap_APPEND]
  \\ CASE_TAC \\ fs []
  \\ PairCases_on `x` \\ fs []
  \\ Cases_on `filter_bitmap x' x1` \\ fs []
  \\ PairCases_on `x` \\ fs []
  \\ rpt var_eq_tac \\ fs []
  \\ fs [word_gc_move_roots_APPEND,LET_THM]
  \\ split_pair_tac \\ fs []
  \\ split_pair_tac \\ fs []
  \\ rpt var_eq_tac \\ fs []
  \\ qpat_assum `filter_bitmap (get_bits h) stack = SOME (x0,x1)` assume_tac
  \\ drule (map_bitmap_APPEND_APPEND |> GEN_ALL)
  \\ `LENGTH x0 = LENGTH ws1` by (imp_res_tac word_gc_move_roots_IMP_LENGTH \\ fs [])
  \\ disch_then drule
  \\ disch_then (qspecl_then [`ws2`,`x'`] mp_tac)
  \\ strip_tac \\ fs [] \\ pop_assum kall_tac
  \\ CASE_TAC \\ fs []
  \\ PairCases_on `x` \\ fs []
  \\ drule filter_bitmap_map_bitmap
  \\ once_rewrite_tac [EQ_SYM_EQ] \\ disch_then drule
  \\ once_rewrite_tac [EQ_SYM_EQ] \\ disch_then drule
  \\ strip_tac \\ rpt var_eq_tac \\ fs []
  \\ CASE_TAC \\ fs []
  \\ PairCases_on `x` \\ fs []);

val bit_length_minus_1 = store_thm("bit_length_minus_1",
  ``w <> 0w ==> bit_length w − 1 = bit_length (w >>> 1)``,
  simp [Once bit_length_def]);

val bit_length_eq_1 = store_thm("bit_length_eq_1",
  ``bit_length w = 1 <=> w = 1w``,
  Cases_on `w = 1w` \\ fs [] THEN1 (EVAL_TAC \\ fs [])
  \\ once_rewrite_tac [bit_length_def] \\ rw []
  \\ once_rewrite_tac [bit_length_def] \\ rw []
  \\ pop_assum mp_tac
  \\ simp_tac std_ss [GSYM w2n_11,w2n_lsr]
  \\ Cases_on `w` \\ fs []
  \\ Cases_on `n` \\ fs []
  \\ Cases_on `n'` \\ fs []
  \\ fs [DIV_EQ_X] \\ decide_tac);

val word_gc_move_bitmap_unroll = prove(
  ``word_gc_move_bitmap conf (w,stack,i1,pa1,curr,m,dm) =
    if w = 0w:'a word then SOME ([],stack,i1,pa1,m,T) else
    if w = 1w then SOME ([],stack,i1,pa1,m,T) else
      case stack of
      | [] => NONE
      | (x::xs) =>
        if ~(w ' 0) then
          case word_gc_move_bitmap conf (w >>> 1,xs,i1,pa1,curr,m,dm) of
          | NONE => NONE
          | SOME (new,stack,i1,pa1,m,c) => SOME (x::new,stack,i1,pa1,m,c)
        else
          let (x1,i1,pa1,m1,c1) = word_gc_move conf (x,i1,pa1,curr,m,dm) in
          case word_gc_move_bitmap conf (w >>> 1,xs,i1,pa1,curr,m1,dm) of
          | NONE => NONE
          | SOME (new,stack,i1,pa1,m,c) => SOME (x1::new,stack,i1,pa1,m,c1 /\ c)``,
  simp [Once word_gc_move_bitmap_def,get_bits_def]
  \\ IF_CASES_TAC
  \\ fs [EVAL ``bit_length 0w``,filter_bitmap_def,
         map_bitmap_def,word_gc_move_roots_def]
  \\ IF_CASES_TAC
  \\ fs [EVAL ``bit_length 1w``,filter_bitmap_def,
         map_bitmap_def,word_gc_move_roots_def]
  \\ simp [bit_length_minus_1]
  \\ fs [GSYM bit_length_eq_1]
  \\ pop_assum (fn th => mp_tac (ONCE_REWRITE_RULE [bit_length_def] th))
  \\ fs [] \\ strip_tac
  \\ Cases_on `bit_length (w >>> 1)` \\ fs []
  \\ fs [GENLIST_CONS,o_DEF,ADD1,filter_bitmap_def]
  \\ Cases_on `stack` \\ fs [] \\ fs [filter_bitmap_def]
  \\ `get_bits (w >>> 1) = GENLIST (\x. w ' (x + 1)) n` by
   (fs [get_bits_def,GENLIST_FUN_EQ] \\ rw []
    \\ `n + 1 <= dimindex (:'a)` by metis_tac [bit_length_LESS_EQ_dimindex]
    \\ `x < dimindex (:'a)` by decide_tac
    \\ fs [word_lsr_def,fcpTheory.FCP_BETA]
    \\ eq_tac \\ fs[] \\ rw [] \\ decide_tac)
  \\ IF_CASES_TAC \\ fs [filter_bitmap_def,map_bitmap_def]
  THEN1
   (fs [word_gc_move_bitmap_def,LET_THM]
    \\ ntac 2 (CASE_TAC \\ fs [])
    \\ split_pair_tac \\ fs []
    \\ rpt (CASE_TAC \\ fs []))
  \\ fs [word_gc_move_bitmap_def,LET_THM]
  \\ CASE_TAC \\ fs [] THEN1 (split_pair_tac \\ fs [])
  \\ CASE_TAC \\ fs [word_gc_move_roots_def,LET_THM]
  \\ ntac 3 (split_pair_tac \\ fs []) \\ rpt var_eq_tac \\ fs []
  \\ fs [map_bitmap_def]
  \\ rpt (CASE_TAC \\ fs[]));

(*

word_gc_move_bitmap_def

*)


val alloc_correct = prove(
  ``alloc w s = (r,t) /\ r <> SOME Error /\
    FLOOKUP s.regs 1 = SOME (Word w) ==>
    ?ck. evaluate
          (Call (SOME (Skip,0,n',m)) (INL 10) NONE,
           s with
           <|use_alloc := F; clock := s.clock + ck;
             code := fromAList (compile c (toAList s.code))|>) =
         (r,
          t with
           <|use_alloc := F; code := fromAList (compile c (toAList s.code))|>)``,
  simp[alloc_def,GSYM AND_IMP_INTRO]
  \\ BasicProvers.CASE_TAC \\ simp[]
  \\ BasicProvers.CASE_TAC \\ simp[]
  \\ BasicProvers.CASE_TAC \\ simp[]
  \\ simp[evaluate_def,find_code_def,lookup_fromAList,compile_def,ALOOKUP_APPEND]
  \\ simp[stubs_def]
  \\ cheat (* correctness of (unimplemented) stubs *));

val find_code_IMP_lookup = prove(
  ``find_code dest regs (s:'a num_map) = SOME x ==>
    ?k. lookup k s = SOME x /\
        (find_code dest regs = ((lookup k):'a num_map -> 'a option))``,
  Cases_on `dest` \\ fs [find_code_def,FUN_EQ_THM]
  \\ every_case_tac \\ fs [] \\ metis_tac []);

val comp_correct = prove(
  ``!p s r t m n c.
      evaluate (p,s) = (r,t) /\ r <> SOME Error /\ good_syntax p /\
      (!k prog. lookup k s.code = SOME prog ==> 30 <= k /\ good_syntax prog) ==>
      ?ck.
        evaluate (FST (comp n m p),
           s with <| clock := s.clock + ck;
                     code := fromAList (stack_alloc$compile c (toAList s.code));
                     use_alloc := F |>) =
          (r, t with
              <| code := fromAList (stack_alloc$compile c (toAList s.code));
                 use_alloc := F |>)``,
  recInduct evaluate_ind \\ rpt strip_tac
  THEN1 (* Skip *)
   (fs [Once comp_def,evaluate_def] \\ rw [] \\ fs [state_component_equality])
  THEN1 (* Halt *)
   (fs [Once comp_def,evaluate_def,get_var_def]
    \\ CASE_TAC \\ fs [] \\ rw [] \\ fs [state_component_equality])
  THEN1 (* Alloc *)
   (fs [evaluate_def,get_var_def]
    \\ fs [Once comp_def,get_var_def]
    \\ every_case_tac \\ fs [good_syntax_def] \\ rw []
    \\ drule alloc_correct \\ fs [])
  THEN1 (* Inst *)
   (fs [Once comp_def] \\ fs [evaluate_def,inst_def]
    \\ CASE_TAC \\ fs [] \\ rw []
    \\ fs [assign_def,word_exp_def,set_var_def,mem_load_def,
         get_var_def,mem_store_def]
    \\ rw [] \\ fs [] \\ fs [state_component_equality]
    \\ every_case_tac \\ fs [markerTheory.Abbrev_def,LET_DEF,word_exp_def]
    \\ fs [state_component_equality] \\ rw [])
  THEN1 (* Get *)
   (fs [Once comp_def,evaluate_def,get_var_def]
    \\ every_case_tac \\ fs [] \\ rw [] \\ fs [set_var_def]
    \\ fs [state_component_equality])
  THEN1 (* Set *)
   (fs [Once comp_def,evaluate_def,get_var_def,set_store_def]
    \\ every_case_tac \\ fs [] \\ rw [] \\ fs [set_var_def]
    \\ fs [state_component_equality])
  THEN1 (* Tick *)
   (qexists_tac `0` \\ fs [Once comp_def,evaluate_def,dec_clock_def]
    \\ every_case_tac \\ fs [] \\ rw [] \\ fs [set_var_def]
    \\ fs [state_component_equality,empty_env_def])
  THEN1 (* Seq *)
   (simp [Once comp_def,dec_clock_def] \\ fs [evaluate_def]
    \\ split_pair_tac \\ fs [LET_DEF]
    \\ split_pair_tac \\ fs [LET_DEF]
    \\ split_pair_tac \\ fs [LET_DEF]
    \\ fs [good_syntax_def,evaluate_def]
    \\ first_x_assum (qspecl_then[`m`,`n`,`c`]mp_tac)
    \\ match_mp_tac IMP_IMP \\ conj_tac
    THEN1 (CCONTR_TAC \\ fs [] \\ fs [] \\ res_tac)
    \\ strip_tac \\ rfs[]
    \\ reverse (Cases_on `res`) \\ fs []
    THEN1 (qexists_tac `ck` \\ fs [AC ADD_COMM ADD_ASSOC,LET_DEF] \\ rw [])
    \\ first_x_assum (qspecl_then[`m'`,`n`,`c`]mp_tac)
    \\ match_mp_tac IMP_IMP \\ conj_tac
    THEN1 (rw [] \\ imp_res_tac evaluate_consts \\ fs [] \\ res_tac \\ fs [])
    \\ strip_tac \\ pop_assum mp_tac
    \\ drule (GEN_ALL evaluate_add_clock) \\ simp []
    \\ disch_then (qspec_then `ck'`assume_tac) \\ strip_tac
    \\ qexists_tac `ck + ck'` \\ fs [AC ADD_COMM ADD_ASSOC]
    \\ imp_res_tac evaluate_consts \\ fs [])
  THEN1 (* Return *)
   (qexists_tac `0` \\ fs [Once comp_def,evaluate_def,get_var_def]
    \\ every_case_tac \\ fs [] \\ rw [] \\ fs [get_var_def]
    \\ fs [state_component_equality,empty_env_def])
  THEN1 (* Raise *)
   (qexists_tac `0` \\ fs [Once comp_def,evaluate_def,get_var_def]
    \\ every_case_tac \\ fs [] \\ rw [] \\ fs [get_var_def]
    \\ fs [state_component_equality,empty_env_def])
  THEN1 (* If *)
   (simp [Once comp_def] \\ fs [evaluate_def,get_var_def]
    \\ split_pair_tac \\ fs [] \\ split_pair_tac \\ fs []
    \\ every_case_tac \\ fs []
    \\ fs [evaluate_def,get_var_def,get_var_imm_case,good_syntax_def]
    \\ rfs []
    THENL [first_x_assum (qspecl_then[`m`,`n`,`c`]mp_tac),
           first_x_assum (qspecl_then[`m'`,`n`,`c`]mp_tac)]
    \\ match_mp_tac IMP_IMP \\ conj_tac
    \\ TRY (rw [] \\ res_tac \\ fs [] \\ NO_TAC)
    \\ strip_tac \\ fs [] \\ rfs []
    \\ qexists_tac `ck` \\ fs [AC ADD_COMM ADD_ASSOC])
  THEN1 (* While *)
   (simp [Once comp_def] \\ fs [evaluate_def,get_var_def]
    \\ split_pair_tac \\ fs []
    \\ reverse every_case_tac \\ fs []
    \\ fs [evaluate_def,get_var_def,get_var_imm_case,good_syntax_def]
    \\ rpt var_eq_tac \\ fs []
    THEN1 (qexists_tac `0` \\ fs [state_component_equality])
    \\ fs [LET_THM] \\ split_pair_tac \\ fs []
    \\ first_x_assum (qspecl_then[`m`,`n`,`c`]mp_tac)
    \\ discharge_hyps THEN1 (fs [] \\ rpt strip_tac \\ res_tac \\ fs [])
    \\ fs [] \\ strip_tac \\ fs []
    \\ Cases_on `res <> NONE` \\ fs []
    THEN1 (rpt var_eq_tac \\ fs []
      \\ qexists_tac `ck` \\ fs [AC ADD_COMM ADD_ASSOC])
    \\ Cases_on `s1.clock = 0` \\ fs []
    THEN1 (rpt var_eq_tac \\ fs []
      \\ qexists_tac `ck` \\ fs [AC ADD_COMM ADD_ASSOC,empty_env_def])
    \\ fs [STOP_def]
    \\ first_x_assum (qspecl_then[`m`,`n`,`c`]mp_tac)
    \\ discharge_hyps
    THEN1 (fs [good_syntax_def] \\ rpt strip_tac \\ res_tac \\ fs []
           \\ imp_res_tac evaluate_consts \\ fs [] \\ res_tac)
    \\ once_rewrite_tac [comp_def] \\ fs [LET_THM]
    \\ strip_tac \\ fs []
    \\ qexists_tac `ck+ck'`
    \\ pop_assum mp_tac
    \\ drule (GEN_ALL evaluate_add_clock) \\ fs []
    \\ disch_then (qspec_then `ck'` assume_tac)
    \\ fs [dec_clock_def] \\ strip_tac
    \\ fs [AC ADD_COMM ADD_ASSOC]
    \\ `ck' + (s1.clock - 1) = ck' + s1.clock - 1` by decide_tac \\ fs []
    \\ imp_res_tac evaluate_consts \\ fs [])
  THEN1 (* JumpLower *)
   (fs [evaluate_def,get_var_def] \\ simp [Once comp_def]
    \\ every_case_tac \\ fs [] \\ rw [] \\ fs [good_syntax_def]
    \\ fs [evaluate_def,get_var_def] \\ fs [find_code_def]
    \\ fs [state_component_equality,empty_env_def] \\ res_tac
    \\ imp_res_tac lookup_IMP_lookup_compile
    \\ pop_assum (qspec_then `c` strip_assume_tac) \\ fs []
    THEN1 (qexists_tac `0` \\ fs [state_component_equality,empty_env_def])
    \\ rfs [] \\ fs [PULL_FORALL,dec_clock_def]
    \\ first_x_assum (qspecl_then[`m1`,`n1`,`c`]mp_tac)
    \\ match_mp_tac IMP_IMP \\ conj_tac
    \\ TRY (rw [] \\ res_tac \\ fs [] \\ NO_TAC) \\ strip_tac \\ fs []
    \\ `ck + s.clock - 1 = ck + (s.clock - 1)` by decide_tac
    \\ qexists_tac `ck` \\ fs [AC ADD_COMM ADD_ASSOC])
  THEN1 (* Call *)
   (fs [evaluate_def] \\ Cases_on `ret` \\ fs [] THEN1
     (Cases_on `find_code dest s.regs s.code` \\ fs []
      \\ every_case_tac \\ fs [empty_env_def] \\ rw [] \\ fs []
      \\ fs [good_syntax_def] \\ simp [Once comp_def,evaluate_def]
      \\ drule find_code_IMP_lookup \\ fs [] \\ rw [] \\ fs [] \\ fs []
      \\ res_tac \\ imp_res_tac lookup_IMP_lookup_compile
      \\ pop_assum (strip_assume_tac o SPEC_ALL) \\ fs []
      THEN1 (qexists_tac `0` \\ fs [empty_env_def,state_component_equality])
      THEN1 (qexists_tac `0` \\ fs [empty_env_def,state_component_equality])
      \\ fs [dec_clock_def]
      \\ first_x_assum (qspecl_then[`n1`,`m1`,`c`]mp_tac)
      \\ match_mp_tac IMP_IMP \\ conj_tac
      \\ TRY (rw [] \\ res_tac \\ fs [] \\ NO_TAC) \\ strip_tac \\ fs []
      \\ `ck + s.clock - 1 = ck + (s.clock - 1)` by decide_tac
      \\ qexists_tac `ck` \\ fs [AC ADD_COMM ADD_ASSOC])
    \\ qmatch_assum_rename_tac `good_syntax (Call (SOME z) dest handler)`
    \\ PairCases_on `z` \\ fs [] \\ simp [Once comp_def] \\ fs []
    \\ split_pair_tac \\ fs []
    \\ Cases_on `find_code dest (s.regs \\ z1) s.code` \\ fs []
    \\ drule find_code_IMP_lookup \\ rw [] \\ fs []
    \\ res_tac \\ imp_res_tac lookup_IMP_lookup_compile
    \\ pop_assum (qspec_then`c`strip_assume_tac) \\ fs [good_syntax_def]
    \\ Cases_on `s.clock = 0` \\ fs [] THEN1
     (rw [] \\ fs [] \\ every_case_tac \\ fs []
      \\ TRY split_pair_tac \\ fs [evaluate_def]
      \\ qexists_tac `0` \\ fs []
      \\ fs [empty_env_def,state_component_equality])
    \\ Cases_on `evaluate (x,dec_clock (set_var z1 (Loc z2 z3) s))`
    \\ Cases_on `q` \\ fs []
    \\ Cases_on `x'` \\ fs [] \\ rw [] \\ TRY
     (every_case_tac \\ fs [] \\ TRY split_pair_tac
      \\ fs [evaluate_def,dec_clock_def,set_var_def]
      \\ first_x_assum (qspecl_then[`n1`,`m1`,`c`]mp_tac)
      \\ match_mp_tac IMP_IMP \\ conj_tac
      \\ TRY (rw [] \\ res_tac \\ fs [] \\ NO_TAC) \\ strip_tac \\ fs []
      \\ `ck + s.clock - 1 = s.clock - 1 + ck` by decide_tac
      \\ qexists_tac `ck` \\ fs [] \\ NO_TAC)
    THEN1
     (Cases_on `w = Loc z2 z3` \\ rw [] \\ fs []
      \\ first_x_assum (qspecl_then[`m`,`n`,`c`]mp_tac)
      \\ match_mp_tac IMP_IMP \\ conj_tac
      \\ TRY (imp_res_tac evaluate_consts \\ fs []
              \\ rw [] \\ res_tac \\ fs [] \\ NO_TAC)
      \\ strip_tac \\ fs [] \\ rfs []
      \\ first_x_assum (qspecl_then[`n1`,`m1`,`c`]mp_tac)
      \\ match_mp_tac IMP_IMP \\ conj_tac
      \\ TRY (imp_res_tac evaluate_consts \\ fs []
              \\ rw [] \\ res_tac \\ fs [] \\ NO_TAC) \\ rw []
      \\ Cases_on `handler` \\ fs []
      \\ TRY (PairCases_on `x'` \\ ntac 2 (split_pair_tac \\ fs []))
      \\ fs [evaluate_def,dec_clock_def,set_var_def]
      \\ first_assum (mp_tac o Q.SPEC `ck` o
             MATCH_MP (REWRITE_RULE [GSYM AND_IMP_INTRO]
             (evaluate_add_clock |> GEN_ALL))) \\ fs []
      \\ rw [] \\ qexists_tac `ck' + ck` \\ fs [AC ADD_COMM ADD_ASSOC]
      \\ `ck + (ck' + (s.clock - 1)) = ck + (ck' + s.clock) - 1` by decide_tac
      \\ fs [] \\ imp_res_tac evaluate_consts \\ fs [])
    \\ Cases_on `handler` \\ fs[]
    \\ fs [evaluate_def,dec_clock_def,set_var_def]
    THEN1
     (first_x_assum (qspecl_then[`n1`,`m1`,`c`]mp_tac)
      \\ match_mp_tac IMP_IMP \\ conj_tac
      \\ TRY (imp_res_tac evaluate_consts \\ fs []
              \\ rw [] \\ res_tac \\ fs [] \\ NO_TAC) \\ rw []
      \\ `ck + s.clock - 1 = s.clock - 1 + ck` by decide_tac
      \\ qexists_tac `ck` \\ fs [])
    \\ PairCases_on `x'` \\ fs []
    \\ split_pair_tac \\ fs []
    \\ fs [evaluate_def,dec_clock_def,set_var_def]
    \\ Cases_on `w = Loc x'1 x'2` \\ rw [] \\ fs []
    \\ ntac 2 (pop_assum mp_tac)
    \\ first_x_assum (qspecl_then[`n1`,`m1`,`c`]mp_tac)
    \\ match_mp_tac IMP_IMP \\ conj_tac
    \\ TRY (imp_res_tac evaluate_consts \\ fs []
            \\ rw [] \\ res_tac \\ fs [] \\ NO_TAC) \\ rw [] \\ rfs[]
    \\ first_x_assum (qspecl_then[`m'`,`n`,`c`]mp_tac)
    \\ match_mp_tac IMP_IMP \\ conj_tac
    \\ TRY (imp_res_tac evaluate_consts \\ fs []
            \\ rw [] \\ res_tac \\ fs [] \\ NO_TAC) \\ rw []
    \\ ntac 2 (pop_assum mp_tac)
    \\ first_assum (mp_tac o Q.SPEC `ck'` o
             MATCH_MP (REWRITE_RULE [GSYM AND_IMP_INTRO]
             (evaluate_add_clock |> GEN_ALL))) \\ fs [] \\ rw []
    \\ qexists_tac `ck+ck'` \\ fs []
    \\ `ck + ck' + s.clock - 1 = s.clock - 1 + ck + ck'` by decide_tac \\ fs[]
    \\ imp_res_tac evaluate_consts \\ fs [])
  THEN1 (* FFI *)
   (qexists_tac `0` \\ fs [Once comp_def,evaluate_def,get_var_def]
    \\ every_case_tac \\ fs [] \\ rw [] \\ fs [get_var_def]
    \\ fs [state_component_equality,empty_env_def,LET_DEF])
  \\ qexists_tac `0` \\ fs [Once comp_def,evaluate_def,get_var_def,set_var_def]
  \\ every_case_tac \\ fs [] \\ rw [] \\ fs [get_var_def]
  \\ fs [state_component_equality,empty_env_def,LET_DEF]
  \\ rw [] \\ fs [] \\ rw []
  \\ fs [state_component_equality,empty_env_def,LET_DEF]);

val compile_semantics = Q.store_thm("compile_semantics",
  `(!k prog. lookup k s.code = SOME prog ==> 30 ≤ k /\ good_syntax prog) /\
   semantics start s <> Fail
   ==>
   semantics start (s with <|
                      code := fromAList (stack_alloc$compile c (toAList s.code));
                      use_alloc := F |>) =
   semantics start s`,
  simp[GSYM AND_IMP_INTRO] >> strip_tac >>
  simp[semantics_def] >>
  IF_CASES_TAC >> fs[] >>
  DEEP_INTRO_TAC some_intro >> fs[] >>
  conj_tac >- (
    gen_tac >> ntac 2 strip_tac >>
    IF_CASES_TAC >> fs[] >- (
      first_x_assum(qspec_then`k'`mp_tac)>>simp[]>>
      (fn g => subterm (fn tm => Cases_on`^(assert has_pair_type tm)`) (#2 g) g) >>
      simp[] >>
      qmatch_assum_rename_tac`_ = (res,_)` >>
      Cases_on`res=SOME Error`>>simp[]>>
      drule comp_correct >>
      simp[good_syntax_def,RIGHT_FORALL_IMP_THM] >>
      discharge_hyps >- metis_tac[] >>
      simp[comp_def] >>
      disch_then(qspec_then`c`strip_assume_tac) >>
      qpat_assum`_ ≠ SOME TimeOut`mp_tac >>
      (fn g => subterm (fn tm => Cases_on`^(assert has_pair_type tm)`) (#2 g) g) >>
      strip_tac >>
      drule (Q.GEN`extra`evaluate_add_clock) >>
      disch_then(qspec_then`ck`mp_tac) >> fs[] >>
      strip_tac >> fsrw_tac[ARITH_ss][] >> rw[]) >>
    DEEP_INTRO_TAC some_intro >> fs[] >>
    conj_tac >- (
      rw[] >>
      Cases_on`r=TimeOut`>>fs[]>-(
        qmatch_assum_abbrev_tac`evaluate (e,ss) = (SOME TimeOut,_)` >>
        qspecl_then[`k'`,`e`,`ss`]mp_tac(GEN_ALL evaluate_add_clock_io_events_mono)>>
        simp[Abbr`ss`] >>
        (fn g => subterm (fn tm => Cases_on`^(assert has_pair_type tm)`) (#2 g) g) >>
        simp[] >> strip_tac >>
        drule comp_correct >>
        simp[RIGHT_FORALL_IMP_THM] >>
        discharge_hyps >- (
          simp[Abbr`e`,good_syntax_def] >>
          reverse conj_tac >- metis_tac[] >>
          rpt(first_x_assum(qspec_then`k+k'`mp_tac))>>rw[] ) >>
        simp[Abbr`e`,comp_def] >>
        disch_then(qspec_then`c`strip_assume_tac) >>
        Cases_on`t'.ffi.final_event`>>fs[] >- (
          ntac 2 (rator_x_assum`evaluate`mp_tac) >>
          drule (GEN_ALL evaluate_add_clock) >>
          disch_then(qspec_then`ck+k`mp_tac) >>
          simp[] >>
          discharge_hyps >- (strip_tac >> fs[]) >>
          simp[] >> ntac 3 strip_tac >>
          rveq >> fs[] >>
          `t'.ffi = r''.ffi` by fs[state_component_equality] >>
          fs[] >>
          Cases_on`t.ffi.final_event`>>fs[] >>
          rfs[] ) >>
        rator_x_assum`evaluate`mp_tac >>
        qmatch_assum_abbrev_tac`evaluate (e,ss) = (_,t')` >>
        qspecl_then[`ck+k`,`e`,`ss`]mp_tac(GEN_ALL evaluate_add_clock_io_events_mono)>>
        simp[Abbr`ss`] >>
        ntac 2 strip_tac >> fs[] >>
        Cases_on`t.ffi.final_event`>>fs[] >>
        rfs[] ) >>
      rator_x_assum`evaluate`mp_tac >>
      drule (GEN_ALL evaluate_add_clock) >>
      disch_then(qspec_then`k'`mp_tac) >>
      simp[] >> strip_tac >>
      drule comp_correct >>
      simp[RIGHT_FORALL_IMP_THM] >>
      discharge_hyps >- (
        simp[good_syntax_def] >>
        reverse conj_tac >- metis_tac[] >>
        rpt(first_x_assum(qspec_then`k+k'`mp_tac))>>rw[] ) >>
      simp[comp_def] >>
      disch_then(qspec_then`c`strip_assume_tac) >>
      strip_tac >>
      qmatch_assum_abbrev_tac`evaluate (e,ss) = _` >>
      qspecl_then[`ck+k`,`e`,`ss`]mp_tac(GEN_ALL evaluate_add_clock_io_events_mono)>>
      simp[Abbr`ss`] >> strip_tac >>
      Cases_on`t'.ffi.final_event`>>fs[]>>
      drule (GEN_ALL evaluate_add_clock) >>
      disch_then(qspec_then`ck+k`mp_tac) >>
      simp[] >>
      discharge_hyps >- (strip_tac >> fs[]) >>
      strip_tac >> fs[] >> rveq >> fs[] >>
      `t.ffi = t'.ffi` by fs[state_component_equality] >>
      BasicProvers.FULL_CASE_TAC >> fs[] >> rfs[] ) >>
    drule comp_correct >>
    simp[RIGHT_FORALL_IMP_THM] >>
    discharge_hyps >- (
      simp[good_syntax_def] >>
      reverse conj_tac >- metis_tac[] >>
      rpt(first_x_assum(qspec_then`k`mp_tac))>>rw[]) >>
    simp[comp_def] >>
    disch_then(qspec_then`c`strip_assume_tac) >>
    asm_exists_tac >> simp[] >>
    BasicProvers.TOP_CASE_TAC >> fs[] >>
    BasicProvers.TOP_CASE_TAC >> fs[]) >>
  strip_tac >>
  IF_CASES_TAC >> fs[] >- (
    first_x_assum(qspec_then`k`mp_tac)>>simp[]>>
    first_x_assum(qspec_then`k`mp_tac)>>
    (fn g => subterm (fn tm => Cases_on`^(assert has_pair_type tm)`) (#2 g) g) >>
    simp[] >>
    rw[] >> BasicProvers.TOP_CASE_TAC >> fs[] >>
    drule comp_correct >>
    simp[good_syntax_def,comp_def] >>
    qexists_tac`c`>>simp[] >>
    conj_tac >- metis_tac[] >>
    rw[] >>
    qpat_assum`_ ≠ SOME TimeOut`mp_tac >>
    (fn g => subterm (fn tm => Cases_on`^(assert has_pair_type tm)`) (#2 g) g) >> rw[] >>
    drule (GEN_ALL evaluate_add_clock) >>
    disch_then(qspec_then`ck`mp_tac)>>simp[] ) >>
  DEEP_INTRO_TAC some_intro >> fs[] >>
  conj_tac >- (
    rw[] >>
    qpat_assum`∀k t. _`(qspec_then`k`mp_tac) >>
    (fn g => subterm (fn tm => Cases_on`^(assert has_pair_type tm)`) (#2 g) g) >>
    simp[] >>
    last_x_assum mp_tac >>
    last_x_assum(qspec_then`k`mp_tac) >>
    rw[] >> BasicProvers.TOP_CASE_TAC >> fs[] >>
    drule comp_correct >>
    simp[good_syntax_def,comp_def] >>
    qexists_tac`c`>>simp[] >>
    conj_tac >- metis_tac[] >>
    rw[] >>
    Cases_on`r=TimeOut`>>fs[]>-(
      qmatch_assum_abbrev_tac`evaluate (e,ss) = (_,t)` >>
      qspecl_then[`ck`,`e`,`ss`]mp_tac(GEN_ALL evaluate_add_clock_io_events_mono)>>
      simp[Abbr`ss`] >>
      Cases_on`t.ffi.final_event`>>fs[] >>
      rpt strip_tac >> fs[] ) >>
    rator_x_assum`evaluate`mp_tac >>
    drule (GEN_ALL evaluate_add_clock) >>
    disch_then(qspec_then`ck`mp_tac)>>simp[] ) >>
  rw[] >>
  qmatch_abbrev_tac`build_lprefix_lub l1 = build_lprefix_lub l2` >>
  `(lprefix_chain l1 ∧ lprefix_chain l2) ∧ equiv_lprefix_chain l1 l2`
    suffices_by metis_tac[build_lprefix_lub_thm,lprefix_lub_new_chain,unique_lprefix_lub] >>
  conj_asm1_tac >- (
    UNABBREV_ALL_TAC >>
    conj_tac >>
    Ho_Rewrite.ONCE_REWRITE_TAC[GSYM o_DEF] >>
    REWRITE_TAC[IMAGE_COMPOSE] >>
    match_mp_tac prefix_chain_lprefix_chain >>
    simp[prefix_chain_def,PULL_EXISTS] >>
    qx_genl_tac[`k1`,`k2`] >>
    qspecl_then[`k1`,`k2`]mp_tac LESS_EQ_CASES >>
    metis_tac[
      LESS_EQ_EXISTS,
      evaluate_add_clock_io_events_mono
        |> CONV_RULE(SWAP_FORALL_CONV)
        |> Q.SPEC`s with <| use_alloc := F; clock := k; code := c|>`
        |> SIMP_RULE(srw_ss())[],
      evaluate_add_clock_io_events_mono
        |> CONV_RULE(SWAP_FORALL_CONV)
        |> Q.SPEC`s with <| clock := k |>`
        |> SIMP_RULE(srw_ss())[]]) >>
  simp[equiv_lprefix_chain_thm] >>
  unabbrev_all_tac >> simp[PULL_EXISTS] >>
  ntac 2 (pop_assum kall_tac) >>
  simp[LNTH_fromList,PULL_EXISTS] >>
  simp[GSYM FORALL_AND_THM] >>
  rpt gen_tac >>
  (fn g => subterm (fn tm => Cases_on`^(assert has_pair_type tm)`) (#2 g) g) >> fs[] >>
  (fn g => subterm (fn tm => Cases_on`^(assert (fn tm => has_pair_type tm andalso free_in tm (#2 g)) tm)`) (#2 g) g) >> fs[] >>
  drule comp_correct >>
  simp[comp_def,RIGHT_FORALL_IMP_THM] >>
  discharge_hyps >- (
    simp[good_syntax_def] >>
    reverse conj_tac >- metis_tac[] >>
    rpt(first_x_assum(qspec_then`k`mp_tac))>>rw[] ) >>
  disch_then(qspec_then`c`strip_assume_tac) >>
  reverse conj_tac >- (
    rw[] >>
    qexists_tac`ck+k`>>simp[] ) >>
  rw[] >>
  qexists_tac`k`>>simp[] >>
  ntac 2 (rator_x_assum`evaluate`mp_tac) >>
  qmatch_assum_abbrev_tac`evaluate (e,ss) = _` >>
  qspecl_then[`ck`,`e`,`ss`]mp_tac(GEN_ALL evaluate_add_clock_io_events_mono)>>
  simp[Abbr`ss`] >>
  ntac 3 strip_tac >> fs[] >>
  fs[IS_PREFIX_APPEND] >>
  simp[EL_APPEND1]);

val make_init_def = Define `
  make_init code s = s with <| code := code; use_alloc := T |>`;

val prog_comp_lambda = Q.store_thm("prog_comp_lambda",
  `prog_comp = λ(n,p). ^(rhs (concl (SPEC_ALL prog_comp_def)))`,
  rw[FUN_EQ_THM,prog_comp_def,LAMBDA_PROD,FORALL_PROD]);

val make_init_semantics = Q.store_thm("make_init_semantics",
  `(!k prog. ALOOKUP code k = SOME prog ==> 30 ≤ k /\ good_syntax prog) /\
   ~s.use_alloc /\ s.code = fromAList (compile c code) /\
   ALL_DISTINCT (MAP FST code) /\
   semantics start (make_init (fromAList code) s) <> Fail ==>
   semantics start s = semantics start (make_init (fromAList code) s)`,
  rw [] \\ drule (ONCE_REWRITE_RULE[CONJ_COMM]compile_semantics)
  \\ fs [make_init_def,lookup_fromAList]
  \\ discharge_hyps THEN1 (rw [] \\ res_tac \\ fs [])
  \\ disch_then (assume_tac o GSYM)
  \\ fs [] \\ AP_TERM_TAC \\ fs [state_component_equality]
  \\ fs [spt_eq_thm,wf_fromAList,lookup_fromAList,compile_def]
  \\ rw []
  \\ rw[ALOOKUP_APPEND] \\ BasicProvers.CASE_TAC
  \\ simp[prog_comp_lambda,ALOOKUP_MAP_gen]
  \\ simp[ALOOKUP_toAList,lookup_fromAList]);

val _ = export_theory();
