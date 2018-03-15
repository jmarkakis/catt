open Var
open Kernel
open Settings
open Common
open MacrosEnvironnement
open Unravel

       
type cmd =
  |DeclCoh of Var.t * (Var.t * ty) list * ty 
  |Check of ((Var.t * ty) list) * tm * (ty option)
  |Decl of Var.t * (Var.t * ty) list * (Var.t * tm) list * tm * (ty option)
	                                  
type prog = cmd list
                
let exec_cmd cmd =
  match cmd with
  | DeclCoh (x,ps,e) ->
     let () = command "let %s = %s"
		      (Var.to_string x)
		      (string_of_ty e)
     in
     let ps = mk_ctx ps in
     let e = unravel_ty ps e in
     let env =
       if !debug_mode then 
	 Kernel.add_env x ps e
       else
	 try Kernel.add_env x ps e
	 with
	 |UnknownId s  -> error "unknown identifier %s" s
	 |UnknownCoh s  -> error "unknown coherence name %s" s
	 |IsNotType s -> error "got %s, but a type was expected" s
	 |HasNoType s -> error "the term %s has no type" s
	 |NotEqual (s1,s2) -> error "got %s, but %s was expected" s1 s2
     in 
     let () = info  "defined" in
     env
  | Check (l, e, t) ->
     let c = Kernel.mk_ctx l in
     let e = fst (unravel_tm c e) in
     let e,t' = Kernel.mk_tm c e in
     begin
     match t with
     |Some t -> let t = unravel_ty c t in
                let t = Kernel.mk_ty c t in
                let () = command "check %s : %s" (string_of_tm e) (string_of_ty t) in
                let () = Kernel.checkEqual c t t' in
                info "checked"
     |None -> let () = command "check %s " (string_of_tm e) in
              info "checked term %s type %s" (string_of_tm e) (string_of_ty t')
     end
  | Decl (v,l,repl,e,t) ->
     let c = Kernel.mk_ctx l in
     let e = replace_bis repl e in 
     let e, vars = unravel_tm c e in
     let e,t' = Kernel.mk_tm c e in 
     let t = match t with
       |Some t -> let t = unravel_ty c t in
                  let t = Kernel.mk_ty c t in
                  let () = Kernel.checkEqual c t t' in
                  let () = command "let %s : %s" (string_of_tm e) (string_of_ty t) in
                  t
       |None -> let () = command "let %s " (string_of_tm e) in
                t'
     in
     let l = List.map fst l in
     let l = List.filter (fun x -> List.mem x vars) l in
     mEnv := (v, (fun l' -> replace l l' (reinit e))) :: (! mEnv);
     info "defined term of type %s" (string_of_ty t)
     
                                       
let rec exec prog =
  let rec aux = function
    |[] -> ()
    |(t::l)  -> exec_cmd t; aux l
  in Kernel.init_env; aux prog
