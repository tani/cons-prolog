:- consult('competitive.pl').
:- consult('competitive-edges.pl').
run_case(Name) :-
    statistics(cputime, ColdStart), once(bench(Name, Expected)), statistics(cputime, ColdEnd),
    Cold is ColdEnd-ColdStart, format('COLD ~w ~9f~n',[Name,Cold]),
    (getenv('BENCH_REPEATS', Text) -> atom_number(Text, Repeats) ; Repeats = 5),
    repeats(Repeats, Name, Expected).
repeats(0, _, _) :- !.
repeats(N, Name, Expected) :-
    (getenv('BENCH_BATCH', Text) -> atom_number(Text, Batch) ; batch_size(Name, Batch)),
    garbage_collect, statistics(cputime, Start), batch_run(Batch, Name, Expected),
    statistics(cputime, End), Total is End-Start, Seconds is Total/Batch,
    format('RESULT ~w ~d ~9f 0 ~d ~9f~n', [Name, Expected, Seconds, Batch, Total]),
    M is N-1, repeats(M, Name, Expected).
batch_run(0, _, _) :- !.
batch_run(N, Name, Expected) :- once(bench(Name, Result)), Result =:= Expected, M is N-1, batch_run(M, Name, Expected).
batch_size(queens, 100). batch_size(tak, 100). batch_size(reverse, 10).
batch_size(qsort, 100). batch_size(graph, 500). batch_size(differentiate, 250).
main :- (getenv('BENCH_CASE', Case) -> downcase_atom(Case, Name), run_case(Name)
         ; (run_case(queens),run_case(tak),run_case(reverse),run_case(qsort),run_case(graph),run_case(differentiate))), halt.
:- initialization(main, main).
