open Common
open Std

module Constraints = struct
  type t = {ty : (ty * ty) list; tm : (tm * tm) list}

  let _to_string c =
    let rec print_ty =
      function
      | [] -> ""
      | (i,t)::c ->
        Printf.sprintf "%s (%s = %s)"
          (print_ty c)
          (Unchecked.ty_to_string i)
          (Unchecked.ty_to_string t)
    in
    let rec print_tm =
      function
      | [] -> ""
      | (i,t)::c ->
        Printf.sprintf "%s (%s = %s)"
          (print_tm c)
          (Unchecked.tm_to_string i)
          (Unchecked.tm_to_string t)
    in
    Printf.sprintf "[%s] [%s]" (print_ty c.ty) (print_tm c.tm)

  let empty = {ty = []; tm = []}

  let  combine c1 c2 =
    {ty = List.append c1.ty c2.ty;
     tm = List.append c1.tm c2.tm}

  let rec  unify_ty ty1 ty2 =
    match ty1, ty2 with
    | Obj, Obj -> empty
    | Arr(a1,u1,v1), Arr(a2,u2,v2) ->
      combine (unify_ty a1 a2)
        (combine
           (unify_tm u1 u2)
           (unify_tm v1 v2))
    | Meta_ty _, _
    | _, Meta_ty _ -> {ty = [(ty1, ty2)]; tm = []}
    | Arr(_,_,_), Obj ->
      raise Error.NeedSuspension
    | Obj, Arr(_,_,_) ->
      raise (Error.NotUnifiable
               (Unchecked.ty_to_string ty1, Unchecked.ty_to_string ty2))
  and unify_tm tm1 tm2 =
    match tm1, tm2 with
    | Var v1, Var v2 when v1 = v2 -> empty
    | Coh(ps1,t1,s1), Coh(ps2,t2,s2) when ps1 = ps2 && t1 = t2 ->
      unify_sub s1 s2
    | Meta_tm _, _
    | _, Meta_tm _ -> {ty = []; tm = [(tm1, tm2)]}
    | Var _, Coh _ | Coh _, Var _ | Var _, Var _ | Coh _ , Coh _ ->
      raise (Error.NotUnifiable
               (Unchecked.tm_to_string tm1, Unchecked.tm_to_string tm2))
  and unify_sub s1 s2 =
    match s1, s2 with
    | [],[] -> empty
    | t1::s1, t2::s2 -> combine (unify_tm t1 t2) (unify_sub s1 s2)
    | [], _::_ | _::_,[] ->
      raise (Error.NotUnifiable
               (Unchecked.sub_ps_to_string s1, Unchecked.sub_ps_to_string s2))

  let rec combine_all = function
    | [] -> empty
    | h::csts -> combine h (combine_all csts)

type mgu = { uty : (int * ty) list; utm : (int * tm) list }

let rec ty_replace_meta_ty (i,ty') ty =
  match ty with
  | Meta_ty j when i = j -> ty'
  | Meta_ty _ -> ty
  | Obj -> Obj
  | Arr(a,u,v) ->
    Arr (ty_replace_meta_ty (i,ty') a, u, v)

let rec tm_replace_meta_tm (i,tm') tm =
  match tm with
  | Meta_tm j when i = j -> tm'
  | Meta_tm _ -> tm
  | Var v -> Var v
  | Coh(ps,t,s) -> Coh(ps,t, List.map (tm_replace_meta_tm (i,tm')) s)

let rec ty_replace_meta_tm (i,tm') ty =
  match ty with
  | Meta_ty _ -> ty
  | Obj -> Obj
  | Arr(a,u,v) ->
    Arr (ty_replace_meta_tm (i,tm') a,
         tm_replace_meta_tm (i,tm') u,
         tm_replace_meta_tm (i,tm') v)

let cst_replace_ty (i,ty) c =
  {ty = List.map_both (ty_replace_meta_ty (i,ty)) c.ty; tm = c.tm}

let cst_replace_tm (i,tm) c =
  let ty_replace = ty_replace_meta_tm (i,tm) in
  let tm_replace = tm_replace_meta_tm (i,tm) in
  {ty = List.map_both ty_replace c.ty;
   tm = List.map_both tm_replace c.tm}

let mgu_replace_ty (i,ty) l =
  {uty = List.map_right (ty_replace_meta_ty (i,ty)) l.uty; utm = l.utm}

let mgu_replace_tm (i,tm) l =
  let ty_replace = ty_replace_meta_tm (i,tm) in
  let tm_replace = tm_replace_meta_tm (i,tm) in
  {uty = List.map_right ty_replace l.uty;
   utm = List.map_right tm_replace l.utm}

let substitute_ty l ty =
  let ty =
    List.fold_left (fun ty (i,tm) -> ty_replace_meta_tm (i,tm) ty) ty l.utm
  in
  List.fold_left (fun ty (i,ty') -> ty_replace_meta_ty (i,ty') ty) ty l.uty

let substitute_tm l tm =
  List.fold_left (fun tm (i,tm') -> tm_replace_meta_tm (i,tm') tm) tm l.utm

  (* Martelli-Montanari algorithm *)
  let resolve_one_step c knowns =
    match c.ty with
    | (ty1,ty2) :: l ->
      let c = {ty = l; tm = c.tm} in
      begin
        match ty1,ty2 with
        | Meta_ty i, Meta_ty j when i = j -> c, knowns
        | Meta_ty i, ty | ty, Meta_ty i ->
          let c = cst_replace_ty (i,ty) c in
          let knowns = mgu_replace_ty (i,ty) knowns in
          c,{uty = (i,ty)::knowns.uty; utm = knowns.utm}
        | ty1, ty2 ->
          let derived_constraints = unify_ty ty1 ty2 in
          combine c derived_constraints, knowns
      end
    | [] ->
      match c.tm with
      | (tm1,tm2) :: l ->
        let c = {ty = c.ty; tm = l} in
        begin
          match tm1,tm2 with
          | Meta_tm i, Meta_tm j when i = j -> c, knowns
          | Meta_tm i, tm | tm, Meta_tm i ->
            let c = cst_replace_tm (i,tm) c in
            let knowns = mgu_replace_tm (i,tm) knowns in
            c,{uty = knowns.uty; utm = (i,tm)::knowns.utm}
          | tm1, tm2 ->
            let derived_constraints = unify_tm tm1 tm2 in
            combine c derived_constraints, knowns
        end
      | [] -> assert false

  let resolve c =
    let rec aux c knowns =
      if c.tm = [] && c.ty = [] then knowns
      else
        let c,knowns = resolve_one_step c knowns in
        aux c knowns
    in aux c {uty = []; utm = []}
end

module Constraints_typing = struct

  let rec tm ctx meta_ctx t =
    Io.info ~v:4 "constraint typing term %s in ctx %s, meta_ctx %s"
      (Unchecked.tm_to_string t)
      (Unchecked.ctx_to_string ctx)
      (Unchecked.meta_ctx_to_string meta_ctx);
      match t with
    | Var v -> t, fst (List.assoc v ctx), Constraints.empty
    | Meta_tm i -> t, List.assoc i meta_ctx, Constraints.empty
    | Coh(ps,t,s)->
      try
        let s,tgt = Unchecked.sub_ps_to_sub s ps in
        let s,cst = sub ctx meta_ctx s tgt in
        Coh(ps,t,(List.map snd s)), Unchecked.ty_apply_sub t s, cst
      with
        Error.NeedSuspension ->
        if !Settings.implicit_suspension then
          let ps = Suspension.ps (Some 1) ps in
          let t = Suspension.ty (Some 1) t in
          let s,meta = Translate_raw.sub_to_suspended s in
          tm ctx (List.append meta meta_ctx) (Coh(ps,t,s))
        else
          raise Error.NotValid
  and sub src meta_ctx s tgt =
    match s,tgt with
    | [],[] -> [], Constraints.empty
    | (x,u)::s, (_,(t,_))::c ->
      let _,cstt = ty tgt meta_ctx t in
      let u,ty,cstu = tm src meta_ctx u in
      let s,csts = sub src meta_ctx s c in
      (x,u)::s,
      Constraints.combine_all
        [cstt;
          cstu;
         Constraints.unify_ty ty (Unchecked.ty_apply_sub t s);
         csts]
    |[],_::_ | _::_, [] -> assert false
  and ty ctx meta_ctx t =
    Io.info ~v:4 "constraint typing type %s in ctx %s, meta_ctx %s"
      (Unchecked.ty_to_string t)
      (Unchecked.ctx_to_string ctx)
      (Unchecked.meta_ctx_to_string meta_ctx);
    match t with
    | Obj -> Obj, Constraints.empty
    | Arr(a,u,v) ->
      let u, tu, cstu = tm ctx meta_ctx u in
      let v, tv, cstv = tm ctx meta_ctx v in
      let a,csta = ty ctx meta_ctx a in
      Arr (a,u,v),
        Constraints.combine_all
          [cstu;
           cstv;
           csta;
           Constraints.unify_ty a tu;
           Constraints.unify_ty a tv]
    | Meta_ty _ -> t, Constraints.empty

  let rec ctx c meta_ctx =
    match c with
    | [] -> [], Constraints.empty
    | (x,(t,expl))::c ->
      let t,cstt = ty c meta_ctx t in
      let c,cstc = ctx c meta_ctx in
      (x,(t,expl))::c,
      Constraints.combine cstc cstt
end

let ctx c =
  let c,meta_ctx = Translate_raw.ctx c in
  let c,cst = Constraints_typing.ctx c meta_ctx in
  Io.info ~v:4 "inferred constraints:%s" (Constraints._to_string cst);
  let cst = Constraints.resolve cst in
  List.map (fun (x,(t,expl)) -> (x,(Constraints.substitute_ty cst t, expl))) c

let ty c ty =
  let ty = Syntax.remove_let_ty ty in
  let ty, meta_ctx = Translate_raw.ty ty in
  let ty,cst = Constraints_typing.ty c meta_ctx ty in
  Constraints.substitute_ty (Constraints.resolve cst) ty

let tm c tm =
  let tm = Syntax.remove_let_tm tm in
  let tm, meta_ctx = Translate_raw.tm tm in
  let tm,_,cst = Constraints_typing.tm c meta_ctx tm in
  Io.info ~v:4 "inferred constraints:%s" (Constraints._to_string cst);
  Constraints.substitute_tm (Constraints.resolve cst) tm

let ty_in_ps ps t =
  let t = Syntax.remove_let_ty t in
  let t, meta_ctx = Translate_raw.ty t in
  let t,cst = Constraints_typing.ty ps meta_ctx t in
  Io.info ~v:4 "inferred constraints:%s" (Constraints._to_string cst);
  let t = Constraints.substitute_ty (Constraints.resolve cst) t in
  let _, names,_ = Unchecked.db_levels ps in
  Unchecked.rename_ty t names

let ps p =
  Kernel.PS.(forget (mk (Kernel.Ctx.check p)))
