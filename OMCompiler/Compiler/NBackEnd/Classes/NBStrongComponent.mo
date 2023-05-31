/*
* This file is part of OpenModelica.
*
* Copyright (c) 1998-2021, Open Source Modelica Consortium (OSMC),
* c/o Linköpings universitet, Department of Computer and Information Science,
* SE-58183 Linköping, Sweden.
*
* All rights reserved.
*
* THIS PROGRAM IS PROVIDED UNDER THE TERMS OF GPL VERSION 3 LICENSE OR
* THIS OSMC PUBLIC LICENSE (OSMC-PL) VERSION 1.2.
* ANY USE, REPRODUCTION OR DISTRIBUTION OF THIS PROGRAM CONSTITUTES
* RECIPIENT'S ACCEPTANCE OF THE OSMC PUBLIC LICENSE OR THE GPL VERSION 3,
* ACCORDING TO RECIPIENTS CHOICE.
*
* The OpenModelica software and the Open Source Modelica
* Consortium (OSMC) Public License (OSMC-PL) are obtained
* from OSMC, either from the above address,
* from the URLs: http://www.ida.liu.se/projects/OpenModelica or
* http://www.openmodelica.org, and in the OpenModelica distribution.
* GNU version 3 is obtained from: http://www.gnu.org/copyleft/gpl.html.
*
* This program is distributed WITHOUT ANY WARRANTY; without
* even the implied warranty of  MERCHANTABILITY or FITNESS
* FOR A PARTICULAR PURPOSE, EXCEPT AS EXPRESSLY SET FORTH
* IN THE BY RECIPIENT SELECTED SUBSIDIARY LICENSE CONDITIONS OF OSMC-PL.
*
* See the full OSMC Public License conditions for more details.
*
*/
encapsulated uniontype NBStrongComponent
"file:        NBStrongComponent.mo
 package:     NBStrongComponent
 description: This file contains the data-types used save the strong Component
              data after causalization.
"
protected
  // selfimport
  import StrongComponent = NBStrongComponent;

  // NF imports
  import ComponentRef = NFComponentRef;
  import Dimension = NFDimension;
  import Expression = NFExpression;
  import Subscript = NFSubscript;
  import Type = NFType;
  import Variable = NFVariable;

  // Backend imports
  import Adjacency = NBAdjacency;
  import NBAdjacency.Mapping;
  import BackendDAE = NBackendDAE;
  import Causalize = NBCausalize;
  import BVariable = NBVariable;
  import NBEquation.{Equation, EquationPointer, EquationPointers, EquationAttributes, Iterator};
  import NBJacobian.JacobianType;
  import Matching = NBMatching;
  import Solve = NBSolve;
  import Sorting = NBSorting;
  import NBSorting.{PseudoBucket, PseudoBucketKey, PseudoBucketValue, SuperNode};
  import BSystem = NBSystem;
  import NBSystem.{System, SystemType};
  import Tearing = NBTearing;
  import NBVariable.{VariablePointer, VariablePointers};

  // Util imports
  import Pointer;
  import Slice = NBSlice;
  import StringUtil;
  import UnorderedMap;
  import UnorderedSet;

public
  uniontype AliasInfo
    record ALIAS_INFO
      SystemType systemType     "The partition type";
      Integer partitionIndex    "the partition index";
      Integer componentIndex    "The index in that strong component array";
    end ALIAS_INFO;

    function toString
      input AliasInfo info;
      output String str = System.systemTypeString(info.systemType) + "[" + intString(info.partitionIndex) + " | " + intString(info.componentIndex) + "]";
    end toString;

    function hash
      input AliasInfo info;
      output Integer i = System.systemTypeInteger(info.systemType) + info.partitionIndex*13 + info.componentIndex*31;
    end hash;

    function isEqual
      input AliasInfo info1;
      input AliasInfo info2;
      output Boolean b = (info1.componentIndex == info2.componentIndex) and (info1.partitionIndex == info2.partitionIndex) and (info1.systemType == info2.systemType);
    end isEqual;
  end AliasInfo;

  record SINGLE_COMPONENT
    "component for all equations that solve for a single (possibly multidimensional) variable
    SCALAR_EQUATION, ARRAY_EQUATION, RECORD_EQUATION."
    Pointer<Variable> var;
    Pointer<Equation> eqn;
    Solve.Status status;
  end SINGLE_COMPONENT;

  record MULTI_COMPONENT
    "component for all equations that can solve for more than one variable instance
    ALGORITHM, WHEN_EQUATION, IF_EQUATION"
    list<Pointer<Variable>> vars;
    Pointer<Equation> eqn;
    Solve.Status status;
  end MULTI_COMPONENT;

  record SLICED_COMPONENT
    "component for all equations AND/OR variables that need to be sliced (zero based indices)"
    ComponentRef var_cref       "cref to solve for";
    Slice<VariablePointer> var  "sliced variable";
    Slice<EquationPointer> eqn  "sliced equation";
    Solve.Status status;
  end SLICED_COMPONENT;

  record GENERIC_COMPONENT
    "component for all equations that need to be sliced but where no for-loop could be recovered
    has no status since this is generated by the Solve module and is always status=EXPLICIT."
    ComponentRef var_cref       "cref to solve for";
    Slice<EquationPointer> eqn  "sliced equation";
  end GENERIC_COMPONENT;

  record ENTWINED_COMPONENT
    "component for entwined SLICED_COMPONENT or GENERIC_COMPONENT
    the body equations have to be called in a specific pattern but do not form an algebraic loop"
    list<StrongComponent> entwined_slices                     "has to be SLICED_COMPONENT()";
    list<tuple<Pointer<Equation>, Integer>> entwined_tpl_lst  "equation with scalar idx (0 based) - fallback scalarization";
  end ENTWINED_COMPONENT;

  record ALGEBRAIC_LOOP
    "component for equations that have to be solved as a system."
    Integer idx;
    Tearing strict;
    Option<Tearing> casual;
    Boolean linear              "true if the loop is linear";
    Boolean mixed               "true for systems that have discrete variables";
    Solve.Status status;
  end ALGEBRAIC_LOOP;

  record ALIAS
    "Component representing equal strong components in ODE<->INIT<->DAE
    has no status since this is generated by the Solve module and is always status=EXPLICIT."
    AliasInfo aliasInfo       "The strong component array and index it refers to";
    StrongComponent original  "The original strong component for analysis";
  end ALIAS;

  function toString
    input StrongComponent comp;
    input Integer index = -1    "negative indices will not be printed";
    output String str;
  protected
    String indexStr = if index > 0 then " " + intString(index) else "";
  algorithm
    str := match comp
      local
        Tearing casual;
        Integer len;

      case SINGLE_COMPONENT() algorithm
        str := StringUtil.headline_3("BLOCK" + indexStr + ": Single Strong Component (status = " + Solve.statusString(comp.status) + ")");
        str := str + "### Variable:\n" + Variable.toString(Pointer.access(comp.var), "\t") + "\n";
        str := str + "### Equation:\n" + Equation.toString(Pointer.access(comp.eqn), "\t") + "\n";
      then str;

      case MULTI_COMPONENT() algorithm
        str := StringUtil.headline_3("BLOCK" + indexStr + ": Multi Strong Component (status = " + Solve.statusString(comp.status) + ")");
        str := str + "### Variables:\n";
        for var in comp.vars loop
          str := str + Variable.toString(Pointer.access(var), "\t") + "\n";
        end for;
        str := str + "\n### Equation:\n" + Equation.toString(Pointer.access(comp.eqn), "\t") + "\n";
      then str;

      case SLICED_COMPONENT() algorithm
        len := listLength(comp.eqn.indices);
        str := if index == -2 then "" else StringUtil.headline_3("BLOCK" + indexStr + ": Sliced Component (status = " + Solve.statusString(comp.status) + ")");
        str := str + "### Variable:\n\t" + ComponentRef.toString(comp.var_cref) + "\n";
        str := str + "### Equation:\n" + Slice.toString(comp.eqn, function Equation.pointerToString(str = "\t")) + "\n";
      then str;

      case ENTWINED_COMPONENT() algorithm
        str := StringUtil.headline_3("BLOCK" + indexStr + ": Entwined Component (status = Solve.EXPLICIT)");
        str := str + "call order: " + List.toString(list(Equation.getEqnName(Util.tuple21(e)) for e in comp.entwined_tpl_lst), ComponentRef.toString, "", "{", ", ", "}", true, 10) + "\n";
        str := str + List.toString(comp.entwined_slices, function toString(index = -2), "", "", "", "");
      then str;

      case GENERIC_COMPONENT() algorithm
        str := StringUtil.headline_3("BLOCK" + indexStr + ": Generic Component (status = Solve.EXPLICIT)");
        str := str + "### Variable:\n\t" + ComponentRef.toString(comp.var_cref) + "\n";
        str := str + "### Equation:\n" + Slice.toString(comp.eqn, function Equation.pointerToString(str = "\t")) + "\n";
      then str;

      case ALGEBRAIC_LOOP() algorithm
        str := StringUtil.headline_3("BLOCK" + indexStr + ": Algebraic Loop (Linear = " + boolString(comp.linear) + ", Mixed = " + boolString(comp.mixed) + ")");
        str := str + Tearing.toString(comp.strict, "Strict Tearing Set");
        if isSome(comp.casual) then
          SOME(casual) := comp.casual;
          str := str + Tearing.toString(casual, "Casual Tearing Set");
        end if;
      then str;

      case ALIAS() algorithm
        str := "--- Alias of " + AliasInfo.toString(comp.aliasInfo) + " ---\n" + toString(comp.original, index);
      then str;

      else algorithm
        Error.addMessage(Error.INTERNAL_ERROR,{getInstanceName() + " failed!"});
      then fail();
    end match;
  end toString;

  function hash
    "only hashes basic types, isEqual is used to differ between sliced/entwined loops"
    input StrongComponent comp;
    output Integer i;
  algorithm
    i := match comp
      case SINGLE_COMPONENT()   then BVariable.hash(comp.var) + Equation.hash(comp.eqn);
      case MULTI_COMPONENT()    then Equation.hash(comp.eqn);
      case SLICED_COMPONENT()   then ComponentRef.hash(comp.var_cref) + Equation.hash(Slice.getT(comp.eqn));
      case GENERIC_COMPONENT()  then Equation.hash(Slice.getT(comp.eqn));
      case ENTWINED_COMPONENT() then sum(hash(sub_comp) for sub_comp in comp.entwined_slices);
      case ALGEBRAIC_LOOP()     then Tearing.hash(comp.strict);
      case ALIAS()              then AliasInfo.hash(comp.aliasInfo);
    end match;
  end hash;

  function isEqual
    input StrongComponent comp1;
    input StrongComponent comp2;
    output Boolean b;
  algorithm
    b := match(comp1, comp2)
      case (SINGLE_COMPONENT(), SINGLE_COMPONENT())     then BVariable.equalName(comp1.var, comp2.var) and Equation.equalName(comp1.eqn, comp2.eqn);
      case (MULTI_COMPONENT(), MULTI_COMPONENT())       then Equation.equalName(comp1.eqn, comp2.eqn);
      case (SLICED_COMPONENT(), SLICED_COMPONENT())     then ComponentRef.isEqual(comp1.var_cref, comp2.var_cref) and Slice.isEqual(comp1.eqn, comp2.eqn, Equation.equalName);
      case (GENERIC_COMPONENT(), GENERIC_COMPONENT())   then Slice.isEqual(comp1.eqn, comp2.eqn, Equation.equalName);
      case (ENTWINED_COMPONENT(), ENTWINED_COMPONENT()) then List.isEqualOnTrue(comp1.entwined_slices, comp2.entwined_slices, isEqual);
      case (ALGEBRAIC_LOOP(), ALGEBRAIC_LOOP())         then Tearing.isEqual(comp1.strict, comp2.strict);
      case (ALIAS(), ALIAS())                           then AliasInfo.isEqual(comp1.aliasInfo, comp2.aliasInfo);
      else false;
    end match;
  end isEqual;

  function createPseudoSlice
    input Integer eqn_arr_idx;
    input ComponentRef cref_to_solve;
    input list<Integer> eqn_scal_indices;
    input EquationPointers eqns;
    input Adjacency.Mapping mapping;
//    input PseudoBucket bucket;
    output StrongComponent slice;
  protected
    Pointer<Equation> eqn_ptr;
    Integer first_eqn;
  algorithm
    // get and save sliced equation
    eqn_ptr := EquationPointers.getEqnAt(eqns, eqn_arr_idx);
    (first_eqn, _) := mapping.eqn_AtS[eqn_arr_idx];

/*
    // mark all scalar indices
    for scal_idx in eqn_scal_indices loop
      arrayUpdate(bucket.marks, scal_idx, true);
    end for;
*/
    // variable slice necessary? if yes fill it!
    slice := SLICED_COMPONENT(
      var_cref    = cref_to_solve,
      var         = Slice.SLICE(BVariable.getVarPointer(cref_to_solve), {}),
      eqn         = Slice.SLICE(eqn_ptr, list(idx - first_eqn for idx in listReverse(eqn_scal_indices))),
      status      = NBSolve.Status.UNPROCESSED
    );
  end createPseudoSlice;

  function createPseudoEntwined
    input list<Integer> eqn_indices;
    input array<Integer> eqn_to_var;
    input Mapping mapping;
    input VariablePointers vars;
    input EquationPointers eqns;
    input list<SuperNode> nodes;
    output StrongComponent entwined;
  protected
    UnorderedMap<Integer, Slice.IntLst> elem_map = UnorderedMap.new<Slice.IntLst>(Util.id, intEq);
    UnorderedMap<Integer, ComponentRef> cref_map = UnorderedMap.new<ComponentRef>(Util.id, intEq);
    list<tuple<Integer, Slice.IntLst>> flat_map;
    Integer arr_idx;
    Slice.IntLst scal_indices;
    list<StrongComponent> entwined_slices = {};
     list<tuple<Pointer<Equation>, Integer>> entwined_tpl_lst;
  algorithm
    // collect individual buckets again
    for idx in eqn_indices loop
      UnorderedMap.add(mapping.eqn_StA[idx], idx :: UnorderedMap.getOrDefault(mapping.eqn_StA[idx], elem_map, {}), elem_map);
    end for;
    // collect crefs to solve for
    for node in nodes loop
      () := match node
        case SuperNode.ARRAY_BUCKET() algorithm
          UnorderedMap.add(node.arr_idx, node.cref_to_solve, cref_map);
        then ();
        else ();
      end match;
    end for;

    // create individual slices
    for tpl in UnorderedMap.toList(elem_map) loop
      (arr_idx, scal_indices) := tpl;
      entwined_slices := createPseudoSlice(arr_idx, UnorderedMap.getSafe(arr_idx, cref_map, sourceInfo()), scal_indices, eqns, mapping) :: entwined_slices;
    end for;

    // create scalar list for fallback
    entwined_tpl_lst := list((EquationPointers.getEqnAt(eqns, mapping.eqn_StA[idx]), idx) for idx in eqn_indices);

    entwined := ENTWINED_COMPONENT(entwined_slices, entwined_tpl_lst);
  end createPseudoEntwined;

  function createAlias
    input SystemType systemType;
    input Integer partitionIndex;
    input Pointer<Integer> index_ptr;
    input StrongComponent orig_comp;
    output StrongComponent alias_comp;
  algorithm
    alias_comp := ALIAS(ALIAS_INFO(systemType, partitionIndex, Pointer.access(index_ptr)), orig_comp);
    Pointer.update(index_ptr, Pointer.access(index_ptr) + 1);
  end createAlias;

  function createPseudoEntwinedIndices
    input array<list<Integer>> entwined_indices;
    input EquationPointers eqns;
    input Adjacency.Mapping mapping;
    output list<tuple<Pointer<Equation>, Integer>> flat_tpl_indices = {};
  protected
    Integer arr_idx, first_idx;
    array<Integer> eqn_StA        "safe access with iterated integer (void pointer)";
  algorithm
    for tmp in entwined_indices loop
      for scal_idx in tmp loop
        eqn_StA := mapping.eqn_StA;
        arr_idx := eqn_StA[scal_idx];
        (first_idx, _) := mapping.eqn_AtS[arr_idx];
        flat_tpl_indices := (EquationPointers.getEqnAt(eqns, arr_idx), scal_idx-first_idx) :: flat_tpl_indices;
      end for;
    end for;
    flat_tpl_indices := listReverse(flat_tpl_indices);
  end createPseudoEntwinedIndices;

  function makeDAEModeResidualTraverse
    " update later to do both inner and residual equations "
    input output Pointer<Equation> eq_ptr;
    input Pointer<list<StrongComponent>> acc;
  protected
    StrongComponent comp;
  algorithm
    comp := match Pointer.access(eq_ptr)
      local
        Pointer<Variable> residualVar;

      case Equation.SCALAR_EQUATION(attr = EquationAttributes.EQUATION_ATTRIBUTES(residualVar = SOME(residualVar)))
      then SINGLE_COMPONENT(residualVar, eq_ptr, NBSolve.Status.UNPROCESSED);

      case Equation.ARRAY_EQUATION(attr = EquationAttributes.EQUATION_ATTRIBUTES(residualVar = SOME(residualVar)))
      then SINGLE_COMPONENT(residualVar, eq_ptr, NBSolve.Status.UNPROCESSED);

      /* are other residuals possible? */

      else algorithm
        Error.addMessage(Error.INTERNAL_ERROR,{getInstanceName() + " failed!"});
      then fail();
    end match;

    Pointer.update(acc, comp :: Pointer.access(acc));
  end makeDAEModeResidualTraverse;

  function fromSolvedEquationSlice
    "creates a strong component assuming the equation is already solved
    todo: if and when equations"
    input Slice<EquationPointer> eqn_slice;
    output StrongComponent comp;
  protected
    EquationPointer eqn = Slice.getT(eqn_slice);
  algorithm
    comp := match Pointer.access(eqn)
      case Equation.SCALAR_EQUATION() then SINGLE_COMPONENT(BVariable.getVarPointer(Expression.toCref(Equation.getLHS(Pointer.access(eqn)))), eqn, NBSolve.Status.EXPLICIT);
      case Equation.ARRAY_EQUATION()  then SINGLE_COMPONENT(BVariable.getVarPointer(Expression.toCref(Equation.getLHS(Pointer.access(eqn)))), eqn, NBSolve.Status.EXPLICIT);
      case Equation.RECORD_EQUATION() then SINGLE_COMPONENT(BVariable.getVarPointer(Expression.toCref(Equation.getLHS(Pointer.access(eqn)))), eqn, NBSolve.Status.EXPLICIT);
      case Equation.FOR_EQUATION()    then SLICED_COMPONENT(ComponentRef.EMPTY(), Slice.SLICE(Pointer.create(NBVariable.DUMMY_VARIABLE), {}), eqn_slice, NBSolve.Status.EXPLICIT);
      // ToDo: the other types
      else algorithm
        Error.addMessage(Error.INTERNAL_ERROR,{getInstanceName() + " failed!"});
      then fail();
    end match;
  end fromSolvedEquationSlice;

  function toSolvedEquation
    "creates a solved equation for an explicitely solved strong component.
    fails if it is not solved explicitely."
    input StrongComponent comp;
    output Pointer<Equation> eqn;
  algorithm
    eqn := match comp
      case SINGLE_COMPONENT(status = NBSolve.Status.EXPLICIT) then comp.eqn;
      case MULTI_COMPONENT(status = NBSolve.Status.EXPLICIT)  then comp.eqn;
      case SLICED_COMPONENT(status = NBSolve.Status.EXPLICIT) then Slice.getT(comp.eqn);
      case GENERIC_COMPONENT()                                then Slice.getT(comp.eqn);
      else algorithm
        Error.addMessage(Error.INTERNAL_ERROR,{getInstanceName() + " failed because strong component could not be
        solved explicitely:\n" + StrongComponent.toString(comp)});
      then fail();
    end match;
  end toSolvedEquation;

  function collectCrefs
    "Collects dependent crefs in current comp and saves them in the
     unordered map. Saves both directions."
    input StrongComponent comp                                "strong component to be analyzed";
    input VariablePointers var_rep                            "scalarized variable representatives";
    input VariablePointers eqn_rep                            "scalarized equation representatives";
    input Mapping var_rep_mapping                             "index mapping for variable representatives";
    input Mapping eqn_rep_mapping                             "index mapping for equation representatives";
    input UnorderedMap<ComponentRef, list<ComponentRef>> map  "unordered map to save the dependencies";
    input UnorderedSet<ComponentRef> set                      "unordered set of array crefs to check for relevance (index lookup)";
    input Boolean pseudo                                      "true if arrays are unscalarized";
    input JacobianType jacType                                "sets the context";
  algorithm
    () := match comp
      local
        Pointer<Equation> eqn_ptr;
        ComponentRef cref;
        list<ComponentRef> dependencies = {}, loop_vars = {}, tmp;
        list<tuple<ComponentRef, list<ComponentRef>>> scalarized_dependencies;
        Tearing strict;
        Equation eqn, body;
        Iterator iter;
        list<ComponentRef> names;
        list<Expression> ranges;

      // sliced array equations - create all the single entries
      case SINGLE_COMPONENT() guard(Equation.isArrayEquation(comp.eqn)) algorithm
        dependencies := Equation.collectCrefs(Pointer.access(comp.eqn), function Slice.getDependentCrefCausalized(set = set));
        scalarized_dependencies := Slice.getDependentCrefsPseudoArrayCausalized(BVariable.getVarName(comp.var), dependencies);
        for tpl in scalarized_dependencies loop
          (cref, dependencies) := tpl;
          updateDependencyMap(cref, dependencies, map, jacType);
        end for;
      then ();

      case SINGLE_COMPONENT() algorithm
        dependencies := Equation.collectCrefs(Pointer.access(comp.eqn), function Slice.getDependentCrefCausalized(set = set));
        dependencies := List.flatten(list(ComponentRef.scalarizeAll(dep) for dep in dependencies));
        updateDependencyMap(BVariable.getVarName(comp.var), dependencies, map, jacType);
      then ();

      case MULTI_COMPONENT() algorithm
        dependencies := Equation.collectCrefs(Pointer.access(comp.eqn), function Slice.getDependentCrefCausalized(set = set));
        dependencies := List.flatten(list(ComponentRef.scalarizeAll(dep) for dep in dependencies));
        for var in comp.vars loop
          updateDependencyMap(BVariable.getVarName(var), dependencies, map, jacType);
        end for;
      then ();

      // sliced for equations - create all the single entries
      case SLICED_COMPONENT() guard(Equation.isForEquation(Slice.getT(comp.eqn))) algorithm
        eqn as Equation.FOR_EQUATION(iter = iter, body = {body}) := Pointer.access(Slice.getT(comp.eqn));
        dependencies := Equation.collectCrefs(eqn, function Slice.getDependentCrefCausalized(set = set));
        if ComponentRef.isEmpty(comp.var_cref) then
          Expression.CREF(cref = cref) := Equation.getLHS(body);
        else
          cref := comp.var_cref;
        end if;
        scalarized_dependencies := Slice.getDependentCrefsPseudoForCausalized(cref, dependencies, var_rep, eqn_rep, var_rep_mapping, eqn_rep_mapping, iter, comp.eqn.indices, false);
        for tpl in listReverse(scalarized_dependencies) loop
          (cref, dependencies) := tpl;
          updateDependencyMap(cref, dependencies, map, jacType);
        end for;
      then ();

      // sliced array equations - create all the single entries
      case SLICED_COMPONENT() guard(Equation.isArrayEquation(Slice.getT(comp.eqn))) algorithm
        eqn as Equation.FOR_EQUATION(iter = iter) := Pointer.access(Slice.getT(comp.eqn));
        dependencies := Equation.collectCrefs(eqn, function Slice.getDependentCrefCausalized(set = set));
        scalarized_dependencies := Slice.getDependentCrefsPseudoArrayCausalized(comp.var_cref, dependencies, comp.eqn.indices);
        for tpl in scalarized_dependencies loop
          (cref, dependencies) := tpl;
          updateDependencyMap(cref, dependencies, map, jacType);
        end for;
      then ();

      // sliced regular equation.
      case SLICED_COMPONENT() algorithm
        eqn := Pointer.access(Slice.getT(comp.eqn));
        dependencies := Equation.collectCrefs(eqn, function Slice.getDependentCrefCausalized(set = set));
        dependencies := List.flatten(list(ComponentRef.scalarizeAll(dep) for dep in dependencies));
        updateDependencyMap(comp.var_cref, dependencies, map, jacType);
      then ();

      // sliced for equations - create all the single entries
      case GENERIC_COMPONENT() guard(Equation.isForEquation(Slice.getT(comp.eqn))) algorithm
        eqn as Equation.FOR_EQUATION(iter = iter, body = {body}) := Pointer.access(Slice.getT(comp.eqn));
        dependencies := Equation.collectCrefs(eqn, function Slice.getDependentCrefCausalized(set = set));
        if ComponentRef.isEmpty(comp.var_cref) then
          Expression.CREF(cref = cref) := Equation.getLHS(body);
        else
          cref := comp.var_cref;
        end if;
        scalarized_dependencies := Slice.getDependentCrefsPseudoForCausalized(cref, dependencies, var_rep, eqn_rep, var_rep_mapping, eqn_rep_mapping, iter, comp.eqn.indices, false);
        for tpl in listReverse(scalarized_dependencies) loop
          (cref, dependencies) := tpl;
          updateDependencyMap(cref, dependencies, map, jacType);
        end for;
      then ();

      case ALGEBRAIC_LOOP(strict = strict) algorithm
        // collect iteration loop vars

        for var in strict.iteration_vars loop
          loop_vars := BVariable.getVarName(Slice.getT(var)) :: loop_vars;
        end for;

        // traverse residual equations and collect dependencies
        for slice in strict.residual_eqns loop
          // ToDo: does this work properly for arrays?
          tmp := Equation.collectCrefs(Pointer.access(Slice.getT(slice)), function Slice.getDependentCrefCausalized(set = set));
          eqn_ptr := Slice.getT(slice);
          if Equation.isForEquation(eqn_ptr) then
            // if its a for equation get all dependencies corresponding to their residual.
            // we do not really care for order and assume full dependency anyway
            eqn as Equation.FOR_EQUATION(iter = iter, body = {body}) := Pointer.access(eqn_ptr);
            cref := Equation.getEqnName(eqn_ptr);
            scalarized_dependencies := Slice.getDependentCrefsPseudoForCausalized(cref, tmp, var_rep, eqn_rep, var_rep_mapping, eqn_rep_mapping, iter, slice.indices, true);
            tmp := List.flatten(list(Util.tuple22(tpl) for tpl in scalarized_dependencies));
          end if;
          dependencies := listAppend(tmp, dependencies);
        end for;

        // traverse inner equations and collect loop vars and dependencies
        for i in 1:arrayLength(strict.innerEquations) loop
          // collect inner equation dependencies
          collectCrefs(strict.innerEquations[i], var_rep, eqn_rep, var_rep_mapping, eqn_rep_mapping, map, set, pseudo, jacType);

          // collect inner loop variables
          loop_vars := listAppend(list(BVariable.getVarName(var) for var in getVariables(strict.innerEquations[i])), loop_vars);
        end for;

        dependencies := List.flatten(list(ComponentRef.scalarizeAll(dep) for dep in dependencies));

        // add all dependencies
        for cref in loop_vars loop
          updateDependencyMap(cref, dependencies, map, jacType);
        end for;
      then ();

      case ALIAS() algorithm
        collectCrefs(comp.original, var_rep, eqn_rep, var_rep_mapping, eqn_rep_mapping, map, set, pseudo, jacType);
      then ();

      /* ToDo add the others and let else case fail! */

      else ();
    end match;
  end collectCrefs;

  function addLoopJacobian
    input output StrongComponent comp;
    input Option<BackendDAE> jac;
  algorithm
    comp := match comp
      local
        Tearing strict;

      case ALGEBRAIC_LOOP(strict = strict) algorithm
        // ToDo: update linearity here
        strict.jac := jac;
        comp.strict := strict;
      then comp;

      else algorithm
        Error.addMessage(Error.INTERNAL_ERROR,{getInstanceName() + " failed because of wrong component: " + toString(comp)});
      then fail();
    end match;
  end addLoopJacobian;

  function getLoopResiduals
    input StrongComponent comp;
    output list<Pointer<Variable>> residuals;
  algorithm
    residuals := match comp
      case ALGEBRAIC_LOOP()  then Tearing.getResidualVars(comp.strict);
                        else {};
    end match;
  end getLoopResiduals;

  function getVariables
    "should this return slices?"
    input StrongComponent comp;
    output list<Pointer<Variable>> vars;
  algorithm
    vars := match comp
      case SINGLE_COMPONENT()   then {comp.var};
      case MULTI_COMPONENT()    then comp.vars;
      case SLICED_COMPONENT()   then {Slice.getT(comp.var)};
      case ENTWINED_COMPONENT() then List.flatten(list(getVariables(slice) for slice in comp.entwined_slices));
      case ALGEBRAIC_LOOP()     then Tearing.getResidualVars(comp.strict); // + inner?
      case ALIAS()              then getVariables(comp.original);
      else algorithm
        Error.addMessage(Error.INTERNAL_ERROR,{getInstanceName() + " failed because of wrong component: " + toString(comp)});
      then fail();
    end match;
  end getVariables;

  function isDiscrete
    "checks if all equations are discrete"
    input StrongComponent comp;
    output Boolean b;
  protected
    function bool_ident "just for usage in List.all"
      input output Boolean b;
    end bool_ident;
  algorithm
    b := match comp
      case SINGLE_COMPONENT()   then Equation.isDiscrete(comp.eqn);
      case MULTI_COMPONENT()    then Equation.isDiscrete(comp.eqn);
      case SLICED_COMPONENT()   then Equation.isDiscrete(Slice.getT(comp.eqn));
      case ENTWINED_COMPONENT() then List.all(list(isDiscrete(c) for c in comp.entwined_slices), bool_ident);
      case GENERIC_COMPONENT()  then Equation.isDiscrete(Slice.getT(comp.eqn));
      case ALGEBRAIC_LOOP()     then not comp.mixed;
      case ALIAS()              then isDiscrete(comp.original);
      else algorithm
        Error.addMessage(Error.INTERNAL_ERROR,{getInstanceName() + " failed because of wrong component: " + toString(comp)});
      then fail();
    end match;
  end isDiscrete;

  function createPseudoScalar
    input list<Integer> comp_indices;
    input array<Integer> eqn_to_var;
    input Adjacency.Mapping mapping;
    input VariablePointers vars;
    input EquationPointers eqns;
    output StrongComponent comp;
  algorithm
    comp := match comp_indices
      local
        Integer i, var_scal_idx, var_arr_idx, size;
        ComponentRef cref;
        Pointer<Variable> var;
        Pointer<Equation> eqn;
        list<Slice<VariablePointer>> comp_vars;
        list<Slice<EquationPointer>> comp_eqns;
        Tearing tearingSet;
        Slice<VariablePointer> var_slice;
        Slice<EquationPointer> eqn_slice;

      // Size 1 strong component
      // - case 1: sliced equation because of sliced variable
      // - case 2: single strong component
      case {i} algorithm
        var_scal_idx := eqn_to_var[i];
        var_arr_idx := mapping.var_StA[var_scal_idx];
        var := VariablePointers.getVarAt(vars, var_arr_idx);
        eqn := EquationPointers.getEqnAt(eqns, mapping.eqn_StA[i]);
        (_, size) := mapping.var_AtS[var_arr_idx];
        if size > 1 or Equation.isForEquation(eqn) then
          // case 1: create the scalar variable and make sliced equation
          cref := VariablePointers.varSlice(vars, var_scal_idx, mapping);
          try
            ({var_slice}, {eqn_slice}) := getLoopVarsAndEqns(comp_indices, eqn_to_var, mapping, vars, eqns);
          else
            Error.addMessage(Error.INTERNAL_ERROR,{getInstanceName() + " failed because single indices did not turn out to be single components."});
            fail();
          end try;
          comp := SLICED_COMPONENT(cref, var_slice, eqn_slice, NBSolve.Status.UNPROCESSED);
        else
          // case 2: just create a single strong component
          comp := match Pointer.access(eqn)
            case Equation.WHEN_EQUATION()   then MULTI_COMPONENT({var}, eqn, NBSolve.Status.UNPROCESSED);
            case Equation.IF_EQUATION()     then MULTI_COMPONENT({var}, eqn, NBSolve.Status.UNPROCESSED);
            case Equation.ALGORITHM()       then MULTI_COMPONENT({var}, eqn, NBSolve.Status.UNPROCESSED);
                                            else SINGLE_COMPONENT(var, eqn, NBSolve.Status.UNPROCESSED);
          end match;
        end if;
      then comp;

      // Size > 1 strong component
      case _ algorithm
        (comp_vars, comp_eqns) := getLoopVarsAndEqns(comp_indices, eqn_to_var, mapping, vars, eqns);
        comp := match (comp_vars, comp_eqns)
          case ({var_slice}, {eqn_slice}) guard(not Equation.isForEquation(Slice.getT(eqn_slice))) algorithm
            if Slice.isFull(var_slice) then
              comp := SINGLE_COMPONENT(
                var       = Slice.getT(var_slice),
                eqn       = Slice.getT(eqn_slice),
                status    = NBSolve.Status.UNPROCESSED);
            else
              comp := SLICED_COMPONENT(
                var_cref  = BVariable.getVarName(Slice.getT(var_slice)),
                var       = var_slice,
                eqn       = eqn_slice,
                status    = NBSolve.Status.UNPROCESSED);
            end if;
          then comp;

          // for equations that are not algebraic loops are caught earlier! Any for equation
          // getting to this point is an actual algebraic loop
          case (_, {eqn_slice}) guard(not Equation.isForEquation(Slice.getT(eqn_slice)))
          then MULTI_COMPONENT(
            vars    = list(Slice.getT(comp_var) for comp_var in comp_vars),
            eqn     = Slice.getT(eqn_slice),
            status  = NBSolve.Status.UNPROCESSED
          );

          else algorithm
            tearingSet := Tearing.TEARING_SET(
              iteration_vars  = comp_vars,
              residual_eqns   = comp_eqns,
              innerEquations  = listArray({}),
              jac             = NONE());
          then ALGEBRAIC_LOOP(
            idx     = -1,
            strict  = tearingSet,
            casual  = NONE(),
            linear  = false,
            mixed   = false,
            status  = NBSolve.Status.IMPLICIT);
        end match;
      then comp;

      else algorithm
        Error.addMessage(Error.INTERNAL_ERROR,{getInstanceName() + " failed."});
      then fail();
    end match;
  end createPseudoScalar;

  // ############################################################
  //                Protected Functions and Types
  // ############################################################

protected
  function getLoopVarsAndEqns
    "adds the equation and matched variable to accumulated lists.
    used to collect algebraic loops.
    ToDo: currently assumes full dependency - update with Slice structures!"
    input list<Integer> comp_indices;
    input array<Integer> eqn_to_var;
    input Adjacency.Mapping mapping;
    input VariablePointers vars;
    input EquationPointers eqns;
    output list<Slice<VariablePointer>> acc_vars = {};
    output list<Slice<EquationPointer>> acc_eqns = {};
  protected
    Integer var_idx, var_arr_idx, var_scal_idx, eqn_arr_idx, eqn_scal_idx;
    list<Integer> idx_lst;
    Pointer<Variable> var;
    Pointer<Equation> eqn;
    UnorderedMap<Integer, Slice.IntLst> var_map = UnorderedMap.new<Slice.IntLst>(Util.id, intEq, listLength(comp_indices));
    UnorderedMap<Integer, Slice.IntLst> eqn_map = UnorderedMap.new<Slice.IntLst>(Util.id, intEq, listLength(comp_indices));
  algorithm
    // store all component var and eqn indices in maps
    for eqn_idx in comp_indices loop
      var_idx           := eqn_to_var[eqn_idx];
      var_arr_idx       := mapping.var_StA[var_idx];
      eqn_arr_idx       := mapping.eqn_StA[eqn_idx];

      // collect variable and equation slices
      idx_lst := if UnorderedMap.contains(var_arr_idx, var_map) then UnorderedMap.getSafe(var_arr_idx, var_map, sourceInfo()) else {};
      UnorderedMap.add(var_arr_idx, var_idx :: idx_lst, var_map);
      idx_lst := if UnorderedMap.contains(eqn_arr_idx, eqn_map) then UnorderedMap.getSafe(eqn_arr_idx, eqn_map, sourceInfo()) else {};
      UnorderedMap.add(eqn_arr_idx, eqn_idx :: idx_lst, eqn_map);
    end for;

    // extract variables and equations from maps
    // check if slices are full and reduce them to base 0 indexing
    for tpl in UnorderedMap.toList(var_map) loop
      (var_arr_idx, idx_lst)  := tpl;
      (var_scal_idx, _)       := mapping.var_AtS[var_arr_idx];
      var                     := VariablePointers.getVarAt(vars, var_arr_idx);
      idx_lst                 := if listLength(idx_lst) == BVariable.size(var) then {} else list(i - var_scal_idx for i in idx_lst);
      acc_vars                := Slice.SLICE(var, idx_lst) :: acc_vars;
    end for;
    for tpl in UnorderedMap.toList(eqn_map) loop
      (eqn_arr_idx, idx_lst)  := tpl;
      (eqn_scal_idx, _)       := mapping.eqn_AtS[eqn_arr_idx];
      eqn                     := EquationPointers.getEqnAt(eqns, eqn_arr_idx);
      idx_lst                 := if listLength(idx_lst) == Equation.size(eqn) then {} else list(i - eqn_scal_idx for i in idx_lst);
      acc_eqns                := Slice.SLICE(eqn, idx_lst) :: acc_eqns;
    end for;
  end getLoopVarsAndEqns;

  function updateDependencyMap
    input ComponentRef cref                                   "cref representing current equation";
    input list<ComponentRef> dependencies                     "the dependency crefs";
    input UnorderedMap<ComponentRef, list<ComponentRef>> map  "unordered map to save the dependencies";
    input JacobianType jacType                                "gives context";
  protected
    list<ComponentRef> tmp_dependencies, fixed_dependencies = {};
  algorithm
    try
      // replace non derivative dependencies with their previous dependencies (also remove self dependency)
      // (be careful with algebraic loops. this here assumes that cyclic dependencies have already been resolved)
      if jacType == NBJacobian.JacobianType.SIMULATION then
        for dep in listReverse(dependencies) loop
          if BVariable.checkCref(dep, BVariable.isState) then
            fixed_dependencies := dep :: fixed_dependencies;
          else
            tmp_dependencies := list(tmp for tmp guard(not ComponentRef.isEqual(tmp, cref)) in UnorderedMap.getSafe(dep, map, sourceInfo()));
            fixed_dependencies := listAppend(tmp_dependencies, fixed_dependencies);
          end if;
        end for;
      else
        // only remove self dependency
        fixed_dependencies := list(tmp for tmp guard(not ComponentRef.isEqual(tmp, cref)) in dependencies);
      end if;
      // update the current value (res/tmp) --> {independent vars}
      UnorderedMap.add(cref, fixed_dependencies, map);
    else
      Error.addMessage(Error.INTERNAL_ERROR,{getInstanceName() + " failed to update " + ComponentRef.toString(cref)
        + " with dependencies " + List.toString(dependencies, ComponentRef.toString) + "."});
    end try;
  end updateDependencyMap;

  annotation(__OpenModelica_Interface="backend");
end NBStrongComponent;
