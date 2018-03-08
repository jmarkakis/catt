%{
    open Common
    open Command
    open ExtSyntax
%}

%token COH OBJ PIPE MOR
%token LPAR RPAR LBRA RBRA COL FS
%token <string> IDENT STRING
%token CHECK EVAL HYP ENV EQUAL LET
%token EOF

%left PIPE
%right MOR

%start prog
%type <Command.prog> prog
%%

prog:
    |cmd prog { $1::$2 }
    |EOF { [] }

cmd:
    |COH IDENT args COL expr FS { DeclCoh (Var.mk $2, (Coh($3,$5), true)) }
    |CHECK args COL expr EQUAL expr FS { Check ($2,$6, Some $4) }
    |CHECK args EQUAL expr FS { Check ($2,$4,None) }
    |LET IDENT args COL expr EQUAL expr FS { Decl (Var.mk $2,$3,$7, Some $5) }
    |LET IDENT args EQUAL expr FS { Decl (Var.mk $2,$3,$5, None) }
    

args:
    |LPAR IDENT COL expr RPAR args { (Var.mk $2, $4)::$6 }
    |{ [] }

sub:
    |simple_expr sub { $1::$2 }	
    |{ [] }

simple_expr:
    |LPAR expr RPAR { $2 }
    |OBJ { Obj, true }
    |IDENT { (Var (Var.mk $1), true) }

subst_expr:
    |simple_expr { $1 }	
    |simple_expr simple_expr sub { (Sub ($1,$2::$3), true) }

expr:
    |subst_expr { $1 }
    |subst_expr MOR subst_expr { (Arr ($1,$3), true) }
    |COH args COL simple_expr { (Coh ($2,$4), true) }
