/*
 * This file is part of OpenModelica.
 *
 * Copyright (c) 1998-CurrentYear, Linköping University,
 * Department of Computer and Information Science,
 * SE-58183 Linköping, Sweden.
 *
 * All rights reserved.
 *
 * THIS PROGRAM IS PROVIDED UNDER THE TERMS OF GPL VERSION 3 
 * AND THIS OSMC PUBLIC LICENSE (OSMC-PL). 
 * ANY USE, REPRODUCTION OR DISTRIBUTION OF THIS PROGRAM CONSTITUTES RECIPIENT'S  
 * ACCEPTANCE OF THE OSMC PUBLIC LICENSE.
 *
 * The OpenModelica software and the Open Source Modelica
 * Consortium (OSMC) Public License (OSMC-PL) are obtained
 * from Linköping University, either from the above address,
 * from the URLs: http://www.ida.liu.se/projects/OpenModelica or  
 * http://www.openmodelica.org, and in the OpenModelica distribution. 
 * GNU version 3 is obtained from: http://www.gnu.org/copyleft/gpl.html.
 *
 * This program is distributed WITHOUT ANY WARRANTY; without
 * even the implied warranty of  MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE, EXCEPT AS EXPRESSLY SET FORTH
 * IN THE BY RECIPIENT SELECTED SUBSIDIARY LICENSE CONDITIONS
 * OF OSMC-PL.
 *
 * See the full OSMC Public License conditions for more details.
 *
 */
  
encapsulated package InlineSolver
" file:        InlineSolver.mo
  package:     InlineSolver 
  description: InlineSolver.mo contains everything needed to set up the 
               BackendDAE for the inline solver

  RCS: $Id$"

public import Absyn;
public import BackendDAE;
public import DAE;
public import Env;

protected import BackendDAEUtil;
protected import BackendDump;
protected import BackendEquation;
protected import BackendVariable;
protected import ComponentReference;
protected import Debug;
protected import Error;
protected import Expression;
protected import Flags;
protected import List;
protected import Util;

// =============================================================================
// section for all public functions
//
// These are functions, that can be used to do anything regarding inline solver.
// =============================================================================

public function generateDAE "function generateDAE
  author: lochel
  This function generates a algebraic system of equations for the inline solver"
  input BackendDAE.BackendDAE inDAE;
  output Option<BackendDAE.BackendDAE> outDAE;
  output Option<BackendDAE.Variables> outInlineVars;
algorithm
  (outDAE, outInlineVars) := matchcontinue(inDAE)
    local
      BackendDAE.BackendDAE dae;
      
    case _ equation /*do nothing */
      false = Flags.isSet(Flags.INLINE_SOLVER);
    then (NONE(), NONE());
    
    case dae equation
      true = Flags.isSet(Flags.INLINE_SOLVER);

      Debug.fcall2(Flags.DUMP_INLINE_SOLVER, BackendDump.dumpBackendDAE, dae, "inlineSolver: raw system");

      /* dae -> algebraic system */      
      dae = dae_to_algSystem(dae);
      
      /* output: algebraic system */
      Debug.fcall2(Flags.DUMP_INLINE_SOLVER, BackendDump.dumpBackendDAE, dae, "inlineSolver: algebraic system");
    then (SOME(dae), NONE());
    
    else equation /* don't work */
      Error.addCompilerWarning("./Compiler/BackEnd/InlineSolver.mo: function generateDAE failed");
      Error.addCompilerWarning("inline solver can not be used.");
    then (NONE(), NONE());
  end matchcontinue;
end generateDAE;

protected function dae_to_algSystem "function dae_to_algSystem
  author: vruge
  This is a helper function for generateDAE.
  Transformation dae in algebraic system"
  input BackendDAE.BackendDAE inDAE;
  output BackendDAE.BackendDAE outDAE;
protected
  BackendDAE.EqSystems systs;
  BackendDAE.EqSystem timesystem;
  BackendDAE.Shared shared;
  
  BackendDAE.Variables orderedVars, vars;
  BackendDAE.EquationArray orderedEqs;
  
  /*need for new matching */
  list<tuple<BackendDAEUtil.pastoptimiseDAEModule, String, Boolean>> pastOptModules;
  tuple<BackendDAEUtil.StructurallySingularSystemHandlerFunc, String, BackendDAEUtil.stateDeselectionFunc, String> daeHandler;
  tuple<BackendDAEUtil.matchingAlgorithmFunc, String> matchingAlgorithm;
  BackendDAE.BackendDAE dae;
  
algorithm
  BackendDAE.DAE(systs, shared) := inDAE;
  ((systs,vars)) := List.fold(systs, eliminatedStatesDerivations,({},BackendVariable.emptyVars()));
  timesystem := timeEquation();
  systs := listAppend(systs, {timesystem});
  shared := addKnowInitialValueForState(shared,vars);
  dae := BackendDAE.DAE(systs, shared);
  
  Debug.fcall2(Flags.DUMP_INLINE_SOLVER, BackendDump.dumpBackendDAE, dae, "inlineSolver: befor mathching algebraic system");
  // matching options
  pastOptModules := BackendDAEUtil.getPastOptModules(SOME({"constantLinearSystem", "removeSimpleEquations", "tearingSystem"}));
  matchingAlgorithm := BackendDAEUtil.getMatchingAlgorithm(NONE());
  daeHandler := BackendDAEUtil.getIndexReductionMethod(NONE());
  
  // solve system
  dae := BackendDAEUtil.transformBackendDAE(dae, SOME((BackendDAE.NO_INDEX_REDUCTION(), BackendDAE.EXACT())), NONE(), NONE());
  // simplify system
  (outDAE, Util.SUCCESS()) := BackendDAEUtil.pastoptimiseDAE(dae, pastOptModules, matchingAlgorithm, daeHandler);
end dae_to_algSystem;

protected function addKnowInitialValueForState "function addKnowInitialValueForState
  author: vruge"
  input BackendDAE.Shared inShared;
  input BackendDAE.Variables invars;
  output BackendDAE.Shared outShared;
protected
  BackendDAE.Var var;
  BackendDAE.Variables knownVars, externalObjects, aliasVars;
  BackendDAE.EquationArray initialEqs;
  BackendDAE.EquationArray removedEqs;
  array< DAE.Constraint> constraints;
  array< DAE.ClassAttributes> classAttrs;
  Env.Cache cache;
  Env.Env env;
  DAE.FunctionTree functionTree;
  BackendDAE.EventInfo eventInfo;
  BackendDAE.ExternalObjectClasses extObjClasses;
  BackendDAE.BackendDAEType backendDAEType;
  BackendDAE.SymbolicJacobians symjacs;  
algorithm
   BackendDAE.SHARED(knownVars=knownVars, externalObjects=externalObjects, aliasVars=aliasVars,initialEqs=initialEqs, removedEqs=removedEqs, constraints=constraints, classAttrs=classAttrs, cache=cache, env=env, functionTree=functionTree, eventInfo=eventInfo, extObjClasses=extObjClasses, backendDAEType=backendDAEType, symjacs=symjacs) := inShared;
   knownVars := BackendVariable.mergeVariables(invars, knownVars);
   outShared := BackendDAE.SHARED(knownVars, externalObjects, aliasVars,initialEqs, removedEqs, constraints, classAttrs, cache, env, functionTree, eventInfo, extObjClasses, backendDAEType, symjacs);
end addKnowInitialValueForState;

protected function timeEquation "function timeEquation
  author: vruge"
  output BackendDAE.EqSystem outEqSystem;
protected 
  BackendDAE.EqSystem eqSystem;
  BackendDAE.Equation eqn;
  BackendDAE.EquationArray eqns;
  DAE.ComponentRef cr,t0,t1,t2,t3,t4;
  DAE.Exp rhs0, lhs0, rhs1, lhs1, rhs2, lhs2, rhs3, lhs3, rhs4, lhs4, dt,t;
  BackendDAE.Variables vars;
  DAE.Type ty;
  BackendDAE.Var var;
algorithm
  ty := DAE.T_REAL_DEFAULT;
  eqns := BackendEquation.emptyEqns();
  vars := BackendVariable.emptyVars();
  ty := DAE.T_REAL_DEFAULT;
  cr := DAE.CREF_IDENT("time", ty, {});
  t0 := ComponentReference.crefPrefixString("$t0", cr);
  t1 := ComponentReference.crefPrefixString("$t1", cr);
  t2 := ComponentReference.crefPrefixString("$t2", cr);
  t3 := ComponentReference.crefPrefixString("$t3", cr);
  t4 := ComponentReference.crefPrefixString("$t4", cr);
  
  (_,var):= stringCrVar("$t0", cr, ty, {});
  vars := BackendVariable.addVar(var, vars);
  (_,var):= stringCrVar("$t1", cr, ty, {});
  vars := BackendVariable.addVar(var, vars);
  (_,var):= stringCrVar("$t2", cr, ty, {});
  vars := BackendVariable.addVar(var, vars);
  (_,var):= stringCrVar("$t3", cr, ty, {});
  vars := BackendVariable.addVar(var, vars);
  (_,var):= stringCrVar("$t4", cr, ty, {});
  vars := BackendVariable.addVar(var, vars);
  
  dt := DAE.CREF(DAE.CREF_IDENT("$dt", ty, {}), DAE.T_REAL_DEFAULT);
  t := DAE.CREF(cr,ty);
  
  lhs0 := DAE.CREF(t0,ty);
  rhs0 := t;
  eqn := BackendDAE.EQUATION(lhs0, rhs0, DAE.emptyElementSource, false);
  eqns := BackendEquation.equationAdd(eqn, eqns);
  
  lhs1 := DAE.CREF(t1,ty);
  rhs1 := eADD(eMUL(eADD(rDIV(1.0,2.0), eMUL(rDIV(-1.0,14.0),sqrt(21.0))),dt),t);
  eqn := BackendDAE.EQUATION(lhs1, rhs1, DAE.emptyElementSource, false);
  eqns := BackendEquation.equationAdd(eqn, eqns);
  
  lhs2 := DAE.CREF(t2,ty);
  rhs2 := eADD(eMUL(rDIV(1.0,2.0),dt),t);
  eqn := BackendDAE.EQUATION(lhs2, rhs2, DAE.emptyElementSource, false);
  eqns := BackendEquation.equationAdd(eqn, eqns);
  
  lhs3 := DAE.CREF(t3,ty);
  rhs3 := eADD(eMUL(eADD(rDIV(1.0,2.0), eMUL(rDIV(1.0,14.0),sqrt(21.0))),dt),t);
  eqn := BackendDAE.EQUATION(lhs3, rhs3, DAE.emptyElementSource, false);
  eqns := BackendEquation.equationAdd(eqn, eqns);
  
  lhs4 := DAE.CREF(t4,ty);
  rhs4 := eADD(dt,t);
  
  eqn := BackendDAE.EQUATION(lhs4, rhs4, DAE.emptyElementSource, false);
  eqns := BackendEquation.equationAdd(eqn, eqns);
  
  eqSystem := BackendDAE.EQSYSTEM(vars, eqns, NONE(), NONE(), BackendDAE.NO_MATCHING(),{});
  (outEqSystem, _, _) := BackendDAEUtil.getIncidenceMatrix(eqSystem, BackendDAE.NORMAL());
end timeEquation;

protected function eliminatedStatesDerivations "function eliminatedStatesDerivations
  author: vruge
  This is a helper function for dae_to_algSystem.
  change function call der(x) in  variable xder
  change kind: state in known variable"
  input BackendDAE.EqSystem inEqSystem;
  input tuple<BackendDAE.EqSystems, BackendDAE.Variables> inTupel ;
  output tuple<BackendDAE.EqSystems, BackendDAE.Variables> outTupel;
protected  
  BackendDAE.Variables orderedVars;
  BackendDAE.Variables vars, invars, outvars;
  BackendDAE.EquationArray orderedEqs;
  BackendDAE.EquationArray eqns, eqns1, eqns2;
  BackendDAE.EqSystem eqSystem;
  BackendDAE.EqSystems inSystems;
  BackendDAE.StateSets stateSets;
algorithm
  BackendDAE.EQSYSTEM(orderedVars=orderedVars, orderedEqs=orderedEqs, stateSets=stateSets) := inEqSystem;
  (inSystems, invars) := inTupel;
  vars := BackendVariable.emptyVars();
  eqns := BackendEquation.emptyEqns();
  eqns2 := BackendEquation.emptyEqns();
  // change function call der(x) in  variable xder
  ((_, eqns1,_,_)) := BackendEquation.traverseBackendDAEEqns(orderedEqs, replaceStates_eqs, (orderedVars, eqns,"$t0","$t0_der"));
  eqns2 :=  BackendEquation.mergeEquationArray(eqns1,eqns2);
  ((_, eqns1,_,_)) := BackendEquation.traverseBackendDAEEqns(orderedEqs, replaceStates_eqs, (orderedVars, eqns,"$t1","$t1_der"));
  eqns2 :=  BackendEquation.mergeEquationArray(eqns1,eqns2);
  ((_, eqns1,_,_)) := BackendEquation.traverseBackendDAEEqns(orderedEqs, replaceStates_eqs, (orderedVars, eqns,"$t2","$t2_der"));
  eqns2 :=  BackendEquation.mergeEquationArray(eqns1,eqns2);
  ((_, eqns1,_,_)) := BackendEquation.traverseBackendDAEEqns(orderedEqs, replaceStates_eqs, (orderedVars, eqns,"$t3","$t3_der"));
  eqns2 :=  BackendEquation.mergeEquationArray(eqns1,eqns2);
  ((_, eqns1,_,_)) := BackendEquation.traverseBackendDAEEqns(orderedEqs, replaceStates_eqs, (orderedVars, eqns,"$t4","$t4_der"));
  eqns2 :=  BackendEquation.mergeEquationArray(eqns1,eqns2);
  // change kind: state in known variable 
  ((vars, eqns, outvars)) := BackendVariable.traverseBackendDAEVars(orderedVars, replaceStates_vars, (vars, eqns2, invars));
  eqSystem := BackendDAE.EQSYSTEM(vars, eqns, NONE(), NONE(), BackendDAE.NO_MATCHING(), stateSets);
  (eqSystem, _, _) := BackendDAEUtil.getIncidenceMatrix(eqSystem, BackendDAE.NORMAL());
  outTupel := (listAppend(inSystems,{eqSystem}), BackendVariable.mergeVariables(invars,outvars));
end eliminatedStatesDerivations;

protected function replaceStates_eqs "function replaceStates_eqs
  author: vruge
  This is a helper function for eliminiertStatesDerivations.
  replace der(x) with $DER.x."
  input tuple<BackendDAE.Equation, tuple<BackendDAE.Variables, BackendDAE.EquationArray, String, String>> inTpl;
  output tuple<BackendDAE.Equation, tuple<BackendDAE.Variables, BackendDAE.EquationArray, String, String>> outTpl;
protected
  BackendDAE.Equation eqn, eqn1;
  BackendDAE.EquationArray eqns;
  BackendDAE.Variables vars;
  String preState;
  String preDer;
algorithm
  (eqn, (vars, eqns, preState, preDer)) := inTpl;
  // replace der(x) with $DER.x
  (eqn1, (_,_,_,_)) := BackendEquation.traverseBackendDAEExpsEqn(eqn, replaceDerStateCref, (vars, 0, preState, preDer));
  eqns := BackendEquation.equationAdd(eqn1, eqns);
  outTpl := (eqn, (vars, eqns,preState,preDer));
end replaceStates_eqs;

protected function replaceDerStateCref "function replaceDerStateCref
  author: vruge
  This is a helper function for dae_to_algSystem."
  input tuple<DAE.Exp, tuple<BackendDAE.Variables, Integer, String, String>> inExp;
  output tuple<DAE.Exp, tuple<BackendDAE.Variables, Integer, String, String>> outExp;
protected
   DAE.Exp e;
   Integer i;
   BackendDAE.Variables vars;
   String preState;
   String preDer;
algorithm
  (e, (vars, i, preState, preDer)) := inExp;
  outExp := Expression.traverseExp(e, replaceDerStateExp, (vars, i,preState,preDer));
end replaceDerStateCref;

protected function replaceDerStateExp "function replaceDerStateExp
  author: vruge
  This is a helper function for replaceDerStateCref."
  input tuple<DAE.Exp, tuple<BackendDAE.Variables, Integer, String, String>> inExp;
  output tuple<DAE.Exp, tuple<BackendDAE.Variables, Integer, String, String>> outExp;
algorithm
  (outExp) := matchcontinue(inExp)
    local
      DAE.ComponentRef cr;
      DAE.Type ty;
      Integer i;
      BackendDAE.Variables vars;
      String preState;
      String preDer; 

    case ((DAE.CALL(path = Absyn.IDENT(name = "der"), expLst = {DAE.CREF(componentRef = cr)}, attr=DAE.CALL_ATTR(ty=ty)), (vars, i,preState,preDer))) equation
      cr = crefPrefixStringWithpopCref(preDer,cr); //der(x) for timepoint t0
    then ((DAE.CREF(cr, ty), (vars, i+1,preState, preDer)));
      
    case ((DAE.CREF(DAE.CREF_IDENT("time", ty, {}), _), (vars, i,preState,preDer))) equation
       cr = DAE.CREF_IDENT("time", ty, {});
       cr = crefPrefixStringWithpopCref(preState,cr);
    then ((DAE.CREF(cr, ty), (vars, i+1, preState, preDer)));
    case ((DAE.CREF(componentRef = cr, ty=ty), (vars, i,preState,preDer))) equation
      true = BackendVariable.isState(cr, vars);
      cr = ComponentReference.crefPrefixString(preState, cr); //x for timepoint t0
    then ((DAE.CREF(cr, ty), (vars, i+1, preState, preDer)));
    
    else
    then inExp;
  end matchcontinue;
end replaceDerStateExp;

protected function crefPrefixStringWithpopCref "function crefPrefixStringWithpopCref 
  author: vruge"
  input String name;
  input DAE.ComponentRef in_cr;
  output DAE.ComponentRef out_cr;
 algorithm
   out_cr := ComponentReference.popCref(in_cr);
   out_cr := ComponentReference.crefPrefixString(name, out_cr);
end crefPrefixStringWithpopCref;

protected function replaceStates_vars "function replaceStates_vars
  author: vruge"
  input tuple<BackendDAE.Var, tuple<BackendDAE.Variables, BackendDAE.EquationArray, BackendDAE.Variables>> inTpl;
  output tuple<BackendDAE.Var, tuple<BackendDAE.Variables, BackendDAE.EquationArray, BackendDAE.Variables>> outTpl;
algorithm
  outTpl := matchcontinue(inTpl)
    local
      BackendDAE.Var var;
      BackendDAE.Variables vars, vars0;
      DAE.ComponentRef cr, x0, x1, x2, x3, x4, derx0, derx1, derx2, derx3, derx4;
      DAE.Type ty;
      DAE.InstDims arryDim;
      BackendDAE.EquationArray eqns;
      //BackendDAE.Equation eqn;
      BackendDAE.EquationArray eqn;
      DAE.Exp dt;
 
    // state
    case((var as BackendDAE.VAR(varName=cr, varKind=BackendDAE.STATE(), varType=ty, arryDim=arryDim), (vars, eqns,vars0))) equation
      var = BackendVariable.setVarKind(var, BackendDAE.VARIABLE());
      vars = BackendVariable.addVar(var, vars);
    
      (x0,_) = stringCrVar("$t0", cr, ty, arryDim); // VarDirection = input
      var = BackendDAE.VAR(x0, BackendDAE.VARIABLE(), DAE.INPUT(), DAE.NON_PARALLEL(), ty, NONE(), NONE(), arryDim, DAE.emptyElementSource, NONE(), NONE(), DAE.NON_CONNECTOR());
      vars0 = BackendVariable.addVar(var, vars0);
      
      (x1,var) = stringCrVar("$t1",cr,ty,arryDim);
      vars = BackendVariable.addVar(var, vars);
      
      (x2,var) = stringCrVar("$t2",cr,ty,arryDim);
      vars = BackendVariable.addVar(var, vars);
      
      (x3,var) = stringCrVar("$t3",cr,ty,arryDim);
      vars = BackendVariable.addVar(var, vars);
      
      (x4,var) = stringCrVar("$t4",cr,ty,arryDim);
      vars = BackendVariable.addVar(var, vars);
      
      (derx0,var) = stringCrVar("$t0_der",cr,ty,arryDim);
      vars = BackendVariable.addVar(var, vars);
      
      (derx1,var) = stringCrVar("$t1_der",cr,ty,arryDim);
      vars = BackendVariable.addVar(var, vars);
      
      (derx2,var) = stringCrVar("$t2_der",cr,ty,arryDim);
      vars = BackendVariable.addVar(var, vars);
      
      (derx3,var) = stringCrVar("$t3_der",cr,ty,arryDim);
      vars = BackendVariable.addVar(var, vars);
      
      (derx4,var) = stringCrVar("$t4_der",cr,ty,arryDim);
      vars = BackendVariable.addVar(var, vars);
      
      dt = DAE.CREF(DAE.CREF_IDENT("$dt", DAE.T_REAL_DEFAULT, {}), DAE.T_REAL_DEFAULT);
      
      //eqn = eulerStep(x0,x1,derx0,dt,ty);
      eqn = stepLobatt(x0, x1, x2, x3, x4, derx0, derx1, derx2, derx3, derx4,dt,ty);
      eqns = BackendEquation.mergeEquationArray(eqn, eqns);
      eqns = BackendEquation.equationAdd(BackendDAE.EQUATION(DAE.CREF(cr, ty), DAE.CREF(x4, ty), DAE.emptyElementSource, false), eqns);
    then ((var, (vars, eqns,vars0)));
    
    // else
    case((var, (vars, eqns,vars0))) equation
      vars = BackendVariable.addVar(var, vars);
    then ((var, (vars, eqns,vars0)));
    
    else equation
      Error.addMessage(Error.INTERNAL_ERROR, {"./Compiler/BackEnd/InlineSolver.mo: function replaceStates1_vars failed"});
    then fail();
  end matchcontinue;
end replaceStates_vars;

protected function stepLobatt "function stepLobatt
  author: vruge
  t1 = t0 + a0*dt"
  input DAE.ComponentRef x0, x1, x2, x3, x4, derx0, derx1, derx2, derx3, derx4;
  input DAE.Exp dt;
  input DAE.Type ty;
  output BackendDAE.EquationArray eqns;
protected
  DAE.Exp rhs1, lhs1, rhs2, lhs2, rhs3, lhs3, rhs4, lhs4, e1, e2,e3, e4,e5,ee1,ee2,ee3,ee4,ee5, a0, a1,a2, a3, a4, d0, d1;
  BackendDAE.Equation eqn;
algorithm
  eqns := BackendEquation.emptyEqns();
  
  ee1 := DAE.CREF(derx0, ty);
  ee2 := DAE.CREF(derx1, ty);
  ee3 := DAE.CREF(derx2, ty);
  ee4 := DAE.CREF(derx3, ty);
  ee5 := DAE.CREF(derx4, ty);
  
  e1 := DAE.CREF(x0, ty);
  e2 := DAE.CREF(x1, ty);
  e3 := DAE.CREF(x2, ty);
  e4 := DAE.CREF(x3, ty);
  e5 := DAE.CREF(x4, ty);
  
  (a0, a1,a2, a3, a4, d0, d1) := coeffsLobattoIIIA1(ty);
  lhs1 := eADD(eMUL(ee1,d0),eMUL(ee2,d1));
  rhs1 :=  eADD(eADD(eADD(eADD(eMUL(e1,a0),eMUL(e2,a1)),eMUL(e3,a2)),eMUL(e4,a3)),eMUL(e5,a4));
  eqn := BackendDAE.EQUATION(lhs1, rhs1, DAE.emptyElementSource, false);
  eqns := BackendEquation.equationAdd(eqn, eqns);
  
  
  (a0, a1,a2, a3, a4, d0, d1) := coeffsLobattoIIIA2(ty);
  lhs2 := eADD(eMUL(ee1,d0),eMUL(ee3,d1));
  rhs2 :=  eADD(eADD(eADD(eADD(eMUL(e1,a0),eMUL(e2,a1)),eMUL(e3,a2)),eMUL(e4,a3)),eMUL(e5,a4));
  eqn := BackendDAE.EQUATION(lhs2, rhs2, DAE.emptyElementSource, false);
  eqns := BackendEquation.equationAdd(eqn, eqns);
  
  (a0, a1,a2, a3, a4, d0, d1) := coeffsLobattoIIIA3(ty);
  lhs3 := eADD(eMUL(ee1,d0),eMUL(ee4,d1));
  rhs3 :=  eADD(eADD(eADD(eADD(eMUL(e1,a0),eMUL(e2,a1)),eMUL(e3,a2)),eMUL(e4,a3)),eMUL(e5,a4));
  eqn := BackendDAE.EQUATION(lhs3, rhs3, DAE.emptyElementSource, false);
  eqns := BackendEquation.equationAdd(eqn, eqns);
  
  (a0, a1,a2, a3, a4, d0, d1) := coeffsLobattoIIIA4(ty);
  lhs4 := eADD(eMUL(ee1,d0),eMUL(ee5,d1));
  rhs4 :=  eADD(eADD(eADD(eADD(eMUL(e1,a0),eMUL(e2,a1)),eMUL(e3,a2)),eMUL(e4,a3)),eMUL(e5,a4));
  eqn := BackendDAE.EQUATION(lhs4, rhs4, DAE.emptyElementSource, false);
  eqns := BackendEquation.equationAdd(eqn, eqns);
end stepLobatt;

protected function stringCrVar "function stringCrVar
  author: vruge"
  input String varTyp;
  input DAE.ComponentRef inCR;
  input DAE.Type ty;
  input DAE.InstDims arryDim;
  output DAE.ComponentRef outCR;
  output BackendDAE.Var var;
algorithm
  outCR := ComponentReference.crefPrefixString(varTyp, inCR);
  var := BackendDAE.VAR(outCR, BackendDAE.VARIABLE(), DAE.BIDIR(), DAE.NON_PARALLEL(), ty, NONE(), NONE(), arryDim, DAE.emptyElementSource, NONE(), NONE(), DAE.NON_CONNECTOR());
end stringCrVar;

protected function rDIV "function rDIV
  author: vruge"
 input Real a;
 input Real b;
 output DAE.Exp c;
algorithm
  c := DAE.BINARY(DAE.RCONST(a),DAE.DIV(DAE.T_REAL_DEFAULT),DAE.RCONST(b));
end rDIV;

protected function eADD "function eADD
  author vruge"
  input DAE.Exp a;
  input DAE.Exp b;
  output DAE.Exp c;
algorithm
  c := DAE.BINARY(a,DAE.ADD(DAE.T_REAL_DEFAULT),b);
end eADD;

protected function eSUB "function eSUB
  author vruge"
  input DAE.Exp a;
  input DAE.Exp b;
  output DAE.Exp c;
algorithm
  c := DAE.BINARY(a,DAE.SUB(DAE.T_REAL_DEFAULT),b);
end eSUB;

protected function eMUL "function eMUL
  author vruge"
  input DAE.Exp a;
  input DAE.Exp b;
  output DAE.Exp c;
algorithm
  c := DAE.BINARY(a,DAE.MUL(DAE.T_REAL_DEFAULT),b);
end eMUL;

protected function eNEG "function eNEG
  author vruge"
  input DAE.Exp a;
  output DAE.Exp c;
algorithm
  c := DAE.UNARY(DAE.UMINUS(DAE.T_REAL_DEFAULT),a);
end eNEG;

protected function sqrt "function sqrt
  author vruge"
  input Real a;
  output DAE.Exp c;
protected
  DAE.Exp b;
algorithm
  b := rDIV(1.0,2.0);
  c := DAE.BINARY(DAE.RCONST(a),DAE.POW(DAE.T_REAL_DEFAULT),b);
end sqrt;

protected function coeffsLobattoIIIA1 "function coeffsLobattoIIIA1
  author vruge"
  input DAE.Type ty;
  output DAE.Exp a0, a1,a2, a3, a4;
  output DAE.Exp d0, d1;
protected
  DAE.Exp e1,e2,e3, sqrt21;
algorithm
  sqrt21 := sqrt(21.0);
  d0 := rDIV(3.0,7.0);
  d1 := DAE.RCONST(1.0);

  e1 := rDIV(81.0, 14.0);
  e2 := rDIV(3.0,14.0);
  e2 := eMUL(sqrt21,e2);
  e3 := eADD(e1,e2);
  a0 := eNEG(e3);

  e1 := rDIV(7.0,2.0);
  e2 := rDIV(1.0,2.0);
  e2 := eMUL(sqrt21,e2);
  a1 := eADD(e1,e2);

  e1 := rDIV(16.0,21.0);
  e1 := eMUL(sqrt21,e1);
  e2 := rDIV(16.0,7.0);
  a2 := eSUB(e1,e2);

  e1 := rDIV(7.0,2.0);
  e2 := rDIV(5.0,6.0);
  e2 := eMUL(sqrt21,e2);
  a3 := eSUB(e1,e2);

  e1 := rDIV(15.0,14.0);
  e2 := rDIV(3.0,14.0);
  e2 := eMUL(sqrt21,e2);
  a4 := eSUB(e1,e2);
end coeffsLobattoIIIA1;

protected function coeffsLobattoIIIA2 "function coeffsLobattoIIIA2
  author vruge"
  input DAE.Type ty;
  output DAE.Exp a0, a1,a2, a3, a4;
  output DAE.Exp d0, d2;
protected
  DAE.Exp e1,e2,e3, sqrt21;
algorithm
  sqrt21 := sqrt(21.0);
  d0 := rDIV(-3.0,8.0);
  d2 := rDIV(1.0,1.0);

  a0 := rDIV(9.0,2.0);

  e1 := rDIV(49.0,48.0);
  e1 := eMUL(sqrt21,e1);
  e2 := rDIV(49.0,16.0);
  e3 := eADD(e1,e2);
  a1 := eNEG(e3);

  a2 := rDIV(2.0,1.0);

  e1 := rDIV(-49.0,16.0);
  e2 := rDIV(49.0,48.0);
  e2 := eMUL(sqrt21,e2);
  a3 := eADD(e1,e2);

  a4 := rDIV(-3.0,8.0);
end coeffsLobattoIIIA2;

protected function coeffsLobattoIIIA3 "function coeffsLobattoIIIA3
  author vruge"
  input DAE.Type ty;
  output DAE.Exp a0, a1,a2, a3, a4;
  output DAE.Exp d0, d3;
protected
  DAE.Exp e1,e2,e3, sqrt21;
algorithm
  sqrt21 := sqrt(21.0);
  d0 := rDIV(3.0,7.0);
  d3 := rDIV(1.0,1.0);

  e1 := rDIV(-81.0,14.0);
  e2 := rDIV(3.0,14.0);
  e2 := eMUL(sqrt21,e2);
  a0 := eADD(e1,e2);

  e1 := rDIV(7.0,2.0);
  e2 := rDIV(5.0,6.0);
  e2 := eMUL(sqrt21,e2);
  a1 := eADD(e1,e2);

  e1 := rDIV(16.0,7.0);
  e2 := rDIV(16.0,21.0);
  e2 := eMUL(sqrt21,e2);
  e3 := eADD(e2,e1);
  a2 := eNEG(e3);

  e1 := rDIV(7.0,2.0);
  e2 := rDIV(-1.0,2.0);
  e2 := eMUL(sqrt21,e2);
  a3 := eADD(e1,e2);

  e1 := rDIV(15.0,14.0);
  e2 := rDIV(3.0,14.0);
  e2 := eMUL(sqrt21,e2);
  a4 := eADD(e1,e2);
end coeffsLobattoIIIA3;

protected function coeffsLobattoIIIA4 "function coeffsLobattoIIIA4
  author vruge"
  input DAE.Type ty;
  output DAE.Exp a0, a1,a2, a3, a4;
  output DAE.Exp d0, d4;
protected
  DAE.Exp e1,e2,e3;
algorithm
  d0 := rDIV(-1.0,1.0);
  d4 := rDIV(1.0,1.0);

  a0 := rDIV(11.0,1.0);
  a1 := rDIV(-49.0,3.0);
  a2 := rDIV(32.0,3.0);
  a3 := a1;
  a4 := a0;
end coeffsLobattoIIIA4;

end InlineSolver;
