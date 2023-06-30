open Syntax
open Variables

type kTy
type kTm

val add_coh_env : var -> (var * ty) list -> ty -> unit
val add_let_env : var -> (var * ty) list -> tm -> string
val add_let_env_of_ty : var -> (var * ty) list -> tm -> ty -> string

val mk_tm : (var * ty) list -> tm -> string * string
val mk_tm_of_ty : (var * ty) list -> tm -> ty -> unit
