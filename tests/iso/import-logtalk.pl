% Framework adapter only: read the upstream tests without loading Logtalk.
% Test goals and expectations are retained; only explicit Logtalk wrappers
% around Prolog goals and supported lgtunit fixture calls are translated.
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(occurs)).
:- op(600, xfy, ::).
:- op(600, fy, ::).
:- op(600, fy, ^^).
:- op(700, xfx, =~=).
:- initialization(main, main).

main :- current_prolog_flag(argv, Args), main(Args), halt.

main([Root, Output]) :-
    set_prolog_flag(iso, true),
    expand_file_name(Root, [Directory]),
    findall(File, test_file(Directory, File), Files0), sort(Files0, Files),
    setup_call_cleanup(open(Output, write, Out, [encoding(utf8)]),
        forall(member(File, Files), import_file(Directory, File, Out)), close(Out)).

test_file(Directory, File) :-
    directory_files(Directory, Names), member(Name, Names),
    \+ memberchk(Name, ['.', '..']), atomic_list_concat([Directory, '/', Name], Path),
    (exists_directory(Path) -> test_file(Path, File); Name == 'tests.lgt', File = Path).

import_file(Root, File, Out) :-
    setup_call_cleanup(open(File, read, In, [encoding(utf8)]),
        read_terms(In, 0, Terms), close(In)),
    atom_concat(Root, Relative0, File), atom_concat('/', Relative, Relative0),
    findall(Clause, (member(row(_, _, Term), Terms), helper_clause(Term, Clause)), Clauses),
    findall(Directive, (member(row(_, _, Term), Terms), source_directive(Term, Directive)), Directives),
    append(Directives, Clauses, ProgramTerms),
    maplist(term_text, ProgramTerms, Texts), atomics_to_string(Texts, "\n", Program),
    forall((member(row(Line, Conditional, Term), Terms), test_clause(Term, Head, Body, Disabled),
            Head =.. [test, Name|Args], test_arguments(Args, Expected, Options),
            atom(Name), sub_atom(Name, 0, 4, _, iso_)),
        emit_case(Out, Relative, Line, Conditional, Disabled, Name, Expected, Options, Body, Program)).

test_arguments([], true, []).
test_arguments([Expected|Options], Expected, Options).

read_terms(In, Depth, Rows) :-
    read_term(In, Term, [syntax_errors(error), double_quotes(codes), term_position(Position)]),
    stream_position_data(line_count, Position, Line),
    (Term == end_of_file ->
        (Depth =:= 0 -> Rows = []; throw(error(unbalanced_conditionals, _)));
        (Term = (:- if(_)) -> Next is Depth+1;
         Term = (:- endif) -> Next is Depth-1; Next = Depth),
        (Next < 0 -> throw(error(unbalanced_conditionals, _)); true),
        Rows = [row(Line, Depth, Term)|Tail], read_terms(In, Next, Tail)).

test_clause((Head :- Body), Head, Body, false) :- compound(Head), functor(Head, test, _).
test_clause((-Head :- Body), Head, Body, true) :- compound(Head), functor(Head, test, _).

helper_clause((Head :- Body), (Head :- Lowered)) :-
    callable(Head), \+ functor(Head, test, _), \+ Head = -_, \+ Head = (:-_),
    lower_goal(Body, Lowered).
helper_clause(Head, Head) :-
    callable(Head), \+ Head = (_:-_), \+ Head = (:-_), \+ Head = -_,
    \+ functor(Head, test, _).
source_directive((:- Declaration), (:- Single)) :-
    Declaration =.. [Kind, PI], memberchk(Kind, [dynamic,multifile,discontiguous]),
    (is_list(PI) -> member(Indicator, PI); Indicator=PI), Single =.. [Kind, Indicator].
source_directive((:- op(P,F,N)), (:- op(P,F,N))).

% Lower in goal positions only: braces inside test data remain ordinary data.
lower_goal(Var, Var) :- var(Var), !.
lower_goal({Goal}, Lowered) :- !, lower_goal(Goal, Lowered).
lower_goal(^^suppress_text_output, true) :- !.
lower_goal(^^set_text_input(Text), iso_test_set_text_input(Text)) :- !.
lower_goal((A,B), (C,D)) :- !, lower_goal(A,C), lower_goal(B,D).
lower_goal((A;B), (C;D)) :- !, lower_goal(A,C), lower_goal(B,D).
lower_goal((A->B), (C->D)) :- !, lower_goal(A,C), lower_goal(B,D).
lower_goal(\+A, \+B) :- !, lower_goal(A,B).
lower_goal(once(A), once(B)) :- !, lower_goal(A,B).
lower_goal(call(A), call(B)) :- nonvar(A), !, lower_goal(A,B).
lower_goal(forall(A,B), forall(C,D)) :- !, lower_goal(A,C), lower_goal(B,D).
lower_goal(catch(A,E,B), catch(C,E,D)) :- !, lower_goal(A,C), lower_goal(B,D).
lower_goal(findall(T,A,L), findall(T,B,L)) :- !, lower_goal(A,B).
lower_goal(bagof(T,A,L), bagof(T,B,L)) :- !, lower_goal(A,B).
lower_goal(setof(T,A,L), setof(T,B,L)) :- !, lower_goal(A,B).
lower_goal(A^B, A^C) :- !, lower_goal(B,C).
lower_goal(assertion(A), iso_test_assertion(A)) :- !.
lower_goal(variant(A,B), iso_test_variant(A,B)) :- !.
lower_goal(A =~= B, iso_test_approximately_equal(A,B)) :- !.
lower_goal(Goal, Goal).

term_text(Term, Text) :-
    term_variables(Term, Variables),
    with_output_to(string(Text), (prolog_term(Term, Variables), write('.'))).
prolog_term(Var, Variables) :- var(Var), !, variable_index(Var, Variables, 0, N), format('V~d', [N]).
prolog_term([], _) :- !, write('[]').
prolog_term([H|T], Variables) :- !,
    write('['), prolog_term(H, Variables), write('|'), prolog_term(T, Variables), write(']').
prolog_term(Number, _) :- number(Number), !, write(Number).
prolog_term(Atom, _) :- atom(Atom), !, quoted_atom(Atom).
prolog_term(Term, Variables) :-
    Term =.. [Name|Args], quoted_atom(Name), write('('), prolog_args(Args, Variables), write(')').
prolog_args([A], Variables) :- !, prolog_term(A, Variables).
prolog_args([A|Args], Variables) :- prolog_term(A, Variables), write(','), prolog_args(Args, Variables).
variable_index(V, [H|T], N, Index) :- (V==H -> Index=N; M is N+1, variable_index(V,T,M,Index)).
quoted_atom(Atom) :-
    put_char('\''), atom_codes(Atom, Codes), maplist(atom_character, Codes), put_char('\'').
atom_character(39) :- !, write('\'\'').
atom_character(92) :- !, write('\\\\').
atom_character(10) :- !, write('\\n').
atom_character(13) :- !, write('\\r').
atom_character(9) :- !, write('\\t').
atom_character(C) :- put_code(C).

emit_case(Out, Relative, Line, Conditional, Disabled, Name, Expected, Options, Body, Program) :-
    lower_goal(Body, Goal),
    expectation(Expected, Goal, Query, ExpectationReason),
    term_text(Query, QueryText), term_text(Expected, ExpectedText),
    findall(Reason, (
        (Conditional > 0, Reason = 'upstream conditional compilation requires adaptation');
        (Disabled == true, Reason = 'upstream marks this test disabled');
        (Options \== [], Reason = 'lgtunit per-test options require adaptation');
        (ExpectationReason \== '', Reason = ExpectationReason);
        (sub_term(Sub, Goal), nonvar(Sub), (Sub = ^^_; Sub = _::_),
         Reason = 'lgtunit fixture or object dispatch requires adaptation')
    ), Reasons0), sort(Reasons0, Reasons),
    format(string(ID), '~w:~w:~d', [Relative, Name, Line]),
    json_value(Out, object([id-ID, name-Name, source-Relative, line-Line,
        program-Program, query-QueryText, expected-ExpectedText, blocked-Reasons])), nl(Out).

json_value(S, object(Pairs)) :- !, put_char(S, '{'), json_pairs(S, Pairs), put_char(S, '}').
json_value(S, List) :- is_list(List), !, put_char(S, '['), json_items(S, List), put_char(S, ']').
json_value(S, Number) :- number(Number), !, write(S, Number).
json_value(S, Text) :-
    (atom(Text) -> atom_codes(Text, Codes); string_codes(Text, Codes)),
    put_char(S, '"'), maplist(json_character(S), Codes), put_char(S, '"').
json_pairs(_, []).
json_pairs(S, [K-V|Pairs]) :-
    json_value(S, K), put_char(S, ':'), json_value(S, V),
    (Pairs=[] -> true; put_char(S, ','), json_pairs(S, Pairs)).
json_items(_, []).
json_items(S, [V|Items]) :-
    json_value(S, V), (Items=[] -> true; put_char(S, ','), json_items(S, Items)).
json_character(S, 34) :- !, write(S, '\\"').
json_character(S, 92) :- !, write(S, '\\\\').
json_character(S, 10) :- !, write(S, '\\n').
json_character(S, 13) :- !, write(S, '\\r').
json_character(S, 9) :- !, write(S, '\\t').
json_character(S, Code) :- Code < 32, !, format(S, '\\u~|~`0t~16r~4+', [Code]).
json_character(S, Code) :- put_code(S, Code).

expectation(true, Goal, Query, '') :- !,
    Query = catch((call(Goal) -> iso_test_result(pass); iso_test_result(fail)), E, iso_test_result(exception(E))).
expectation(false, Goal, Query, '') :- !,
    Query = catch((call(Goal) -> iso_test_result(fail); iso_test_result(pass)), E, iso_test_result(exception(E))).
expectation(fail, Goal, Query, Reason) :- !, expectation(false, Goal, Query, Reason).
expectation(exists(Post), Goal, Query, '') :- !,
    lower_goal(Post, LoweredPost),
    Query = catch(((call(Goal),call(LoweredPost)) -> iso_test_result(pass); iso_test_result(fail)),
                  E, iso_test_result(exception(E))).
expectation(true(Post), Goal, Query, '') :- !,
    lower_goal(Post, LoweredPost),
    Query = catch((call(Goal) -> (call(LoweredPost) -> iso_test_result(pass); iso_test_result(post_failed(Post))); iso_test_result(fail)),
                  E, iso_test_result(exception(E))).
expectation(variant(A,B), Goal, Query, '') :- !,
    Query = catch((call(Goal) -> (iso_test_variant(A,B) -> iso_test_result(pass); iso_test_result(post_failed(variant(A,B)))); iso_test_result(fail)),
                  E, iso_test_result(exception(E))).
expectation(subsumes(A,B), Goal, Query, Reason) :- !,
    expectation(true(subsumes_term(A,B)), Goal, Query, Reason).
expectation(ball(Ball), Goal, Query, '') :- !,
    Query = catch((call(Goal) -> iso_test_result(missing_ball); iso_test_result(missing_ball)),
                  E, (E=Ball -> iso_test_result(pass); iso_test_result(wrong_ball(E)))).
expectation(error(Formal), Goal, Query, '') :- !,
    Query = catch((call(Goal) -> iso_test_result(missing_error); iso_test_result(missing_error)),
        E, (E = error(Formal,_) -> iso_test_result(pass); iso_test_result(wrong_error(E)))).
expectation(errors(Formals), Goal, Query, '') :- !,
    Query = catch((call(Goal) -> iso_test_result(missing_error); iso_test_result(missing_error)),
        E, (iso_test_error_member(E,Formals) -> iso_test_result(pass); iso_test_result(wrong_error(E)))).
expectation(_, _, iso_test_result(blocked), 'lgtunit expectation requires adaptation').
