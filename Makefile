# DO NOT DELETE: Beginning of Haskell dependencies
Connections.o : Connections.hs
CTT.o : CTT.hs
CTT.o : Connections.hi
Eval.o : Eval.hs
Eval.o : CTT.hi
Eval.o : Connections.hi
Exp/Abs.o : Exp/Abs.hs
Exp/ErrM.o : Exp/ErrM.hs
Exp/Lex.o : Exp/Lex.hs
Exp/Layout.o : Exp/Layout.hs
Exp/Layout.o : Exp/Lex.hi
Exp/Par.o : Exp/Par.hs
Exp/Par.o : Exp/Lex.hi
Exp/Par.o : Exp/Abs.hi
Exp/Print.o : Exp/Print.hs
Exp/Print.o : Exp/Abs.hi
Exp/Skel.o : Exp/Skel.hs
Exp/Skel.o : Exp/Abs.hi
Exp/Test.o : Exp/Test.hs
Exp/Test.o : Exp/Skel.hi
Exp/Test.o : Exp/Print.hi
Exp/Test.o : Exp/Par.hi
Exp/Test.o : Exp/Lex.hi
Exp/Test.o : Exp/Layout.hi
Exp/Test.o : Exp/Abs.hi
Resolver.o : Resolver.hs
Resolver.o : Connections.hi
Resolver.o : Connections.hi
Resolver.o : CTT.hi
Resolver.o : CTT.hi
Resolver.o : Exp/Abs.hi
TypeChecker.o : TypeChecker.hs
TypeChecker.o : Eval.hi
TypeChecker.o : CTT.hi
TypeChecker.o : Connections.hi
Main.o : Main.hs
Main.o : Eval.hi
Main.o : TypeChecker.hi
Main.o : Resolver.hi
Main.o : CTT.hi
Main.o : Exp/ErrM.hi
Main.o : Exp/Layout.hi
Main.o : Exp/Abs.hi
Main.o : Exp/Print.hi
Main.o : Exp/Par.hi
Main.o : Exp/Lex.hi
# DO NOT DELETE: End of Haskell dependencies
