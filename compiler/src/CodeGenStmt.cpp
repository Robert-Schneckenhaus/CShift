#include "CodeGen.h"

#include <llvm/IR/CFG.h>
#include <llvm/IR/Constants.h>

// ---------------------------------------------------------------------------
// Blocks, scopes and cleanup
// ---------------------------------------------------------------------------

// Error<void>: a result that carries no value on success.
bool CodeGen::isVoidResult(Type* t) const
{
    return t->isError() && t->elem->isVoid();
}

bool CodeGen::blockOpen() const
{
    llvm::BasicBlock* bb = builder.GetInsertBlock();
    return bb && !bb->getTerminator();
}

// True if the insertion point can (probably) be reached at run time.
bool CodeGen::reachable() const
{
    llvm::BasicBlock* bb = builder.GetInsertBlock();
    if (!bb || bb->getTerminator())
        return false;
    if (fs->deadBlocks.count(bb))
        return false;
    if (bb == &fs->fn->getEntryBlock())
        return true;
    return !llvm::pred_empty(bb);
}

// After a terminator (return/break/continue) further statements go into an unreachable block.
void CodeGen::ensureInsertPoint()
{
    if (blockOpen())
        return;
    llvm::BasicBlock* dead = newBlock("dead");
    fs->deadBlocks.insert(dead);
    builder.SetInsertPoint(dead);
}

llvm::BasicBlock* CodeGen::newBlock(const char* name)
{
    return llvm::BasicBlock::Create(ctx, name, fs->fn);
}

void CodeGen::setBlock(llvm::BasicBlock* bb)
{
    builder.SetInsertPoint(bb);
}

void CodeGen::branchTo(llvm::BasicBlock* bb)
{
    if (blockOpen())
        builder.CreateBr(bb);
}

void CodeGen::pushScope()
{
    fs->scopes.emplace_back();
}

void CodeGen::popScope(bool emitCleanup)
{
    if (emitCleanup && blockOpen())
        emitScopeCleanup(fs->scopes.back());
    fs->scopes.pop_back();
}

void CodeGen::emitScopeCleanup(const Scope& scope)
{
    for (size_t i = scope.vars.size(); i > 0; i -= 1)
    {
        const ScopeVar& v = scope.vars[i - 1];
        if (v.disposable)
            callDispose(v);
        if (v.ownsArc && !v.isRef)
        {
            llvm::Value* val = builder.CreateLoad(llvmTypeOf(v.type), v.slot);
            emitReleaseValue(v.type, val);
            if (v.resetOnCleanup)
                builder.CreateStore(llvm::Constant::getNullValue(llvmTypeOf(v.type)), v.slot);
        }
    }
}

// Emits cleanup code for all scopes above 'depth' without popping them (used by return/break/continue).
void CodeGen::emitCleanupsDownTo(size_t depth)
{
    for (size_t s = fs->scopes.size(); s > depth; s -= 1)
        emitScopeCleanup(fs->scopes[s - 1]);
}

ScopeVar& CodeGen::declareVar(const std::string& name, Type* type, llvm::Value* slot)
{
    ScopeVar v;
    v.name = name;
    v.type = type;
    v.slot = slot;
    v.ownsArc = needsArc(type);
    fs->scopes.back().vars.push_back(v);
    return fs->scopes.back().vars.back();
}

// ---------------------------------------------------------------------------
// Function bodies
// ---------------------------------------------------------------------------

void CodeGen::emitFunctionBody(FuncInfo& fi)
{
    fs = std::make_unique<FnState>();
    fs->func = &fi;
    fs->fn = fi.fn;
    fs->retType = fi.ret;
    fs->isIntMain = (&fi == mainFunc) && fi.ret->isInt();

    llvm::BasicBlock* entry = llvm::BasicBlock::Create(ctx, "entry", fi.fn);
    builder.SetInsertPoint(entry);
    pushScope();

    try
    {
        auto argIt = fi.fn->arg_begin();
        auto* ptrTy = llvm::PointerType::getUnqual(ctx);
        if (fi.hasThis)
        {
            llvm::AllocaInst* slot = entryAlloca(ptrTy, "this");
            builder.CreateStore(&*argIt, slot);
            fs->thisSlot = slot;
            ++argIt;
        }
        for (size_t i = 0; i < fi.paramTypes.size(); i += 1)
        {
            Type* pt = fi.paramTypes[i];
            const std::string& name = fi.decl->params[i].name;
            llvm::Argument* arg = &*argIt++;
            if (fi.paramRefs[i] != RefKind::None)
            {
                llvm::AllocaInst* slot = entryAlloca(ptrTy, name);
                builder.CreateStore(arg, slot);
                ScopeVar& v = declareVar(name, pt, slot);
                v.isRef = true;
                v.isConst = fi.paramRefs[i] == RefKind::ConstRef;
                v.ownsArc = false;
            }
            else
            {
                llvm::AllocaInst* slot = entryAlloca(llvmTypeOf(pt), name);
                builder.CreateStore(arg, slot);
                emitRetainValue(pt, arg); // the callee owns its copy of the parameter
                declareVar(name, pt, slot);
            }
        }

        emitBlock(fi.decl->body.get(), true);

        if (blockOpen())
        {
            if (!reachable())
            {
                builder.CreateUnreachable();
            }
            else if (fi.ret->isVoid())
            {
                emitCleanupsDownTo(0);
                builder.CreateRetVoid();
            }
            else if (isVoidResult(fi.ret))
            {
                // Falling off the end of an Error<void> function means success.
                emitCleanupsDownTo(0);
                builder.CreateRet(makeSome(fi.ret, nullptr));
            }
            else
            {
                diag.error(fi.decl->loc, "not all code paths of '" + fi.name + "' return a value");
                builder.CreateUnreachable();
            }
        }
    }
    catch (const CompileError& e)
    {
        diag.error(e);
    }

    // Terminate any block that was left open after an error.
    for (llvm::BasicBlock& bb : *fi.fn)
        if (!bb.getTerminator())
        {
            builder.SetInsertPoint(&bb);
            builder.CreateUnreachable();
        }
    fs.reset();
}

void CodeGen::emitBlock(BlockStmt* b, bool newScope)
{
    bool oldChecked = fs->checked;
    if (b->isUnsafe)
        fs->unsafeDepth += 1;
    if (b->isUnchecked)
        fs->checked = false;
    if (newScope)
        pushScope();
    for (auto& s : b->stmts)
        emitStmt(s.get());
    if (newScope)
        popScope(true);
    if (b->isUnsafe)
        fs->unsafeDepth -= 1;
    fs->checked = oldChecked;
}

// ---------------------------------------------------------------------------
// Statements
// ---------------------------------------------------------------------------

void CodeGen::emitStmt(Stmt* s)
{
    ensureInsertPoint();
    size_t scopeCount = fs->scopes.size();
    size_t loopCount = fs->loops.size();
    int unsafeDepth = fs->unsafeDepth;
    bool checked = fs->checked;

    try
    {
        switch (s->kind)
        {
        case StmtKind::Block: emitBlock(static_cast<BlockStmt*>(s)); break;
        case StmtKind::VarDecl: emitVarDecl(static_cast<VarDeclStmt*>(s)); break;
        case StmtKind::Expr: emitExprStmt(static_cast<ExprStmt*>(s)); break;
        case StmtKind::If: emitIf(static_cast<IfStmt*>(s)); break;
        case StmtKind::While: emitWhile(static_cast<WhileStmt*>(s)); break;
        case StmtKind::DoWhile: emitDoWhile(static_cast<DoWhileStmt*>(s)); break;
        case StmtKind::For: emitFor(static_cast<ForStmt*>(s)); break;
        case StmtKind::Foreach: emitForeach(static_cast<ForeachStmt*>(s)); break;
        case StmtKind::Switch: emitSwitch(static_cast<SwitchStmt*>(s)); break;
        case StmtKind::Break: emitBreakContinue(true, s->loc); break;
        case StmtKind::Continue: emitBreakContinue(false, s->loc); break;
        case StmtKind::Return: emitReturn(static_cast<ReturnStmt*>(s)); break;
        case StmtKind::UsingBlock: emitUsingBlock(static_cast<UsingBlockStmt*>(s)); break;
        case StmtKind::Empty: break;
        }
    }
    catch (const CompileError& e)
    {
        diag.error(e);
        fs->temps.clear();
        fs->scopes.resize(scopeCount);
        fs->loops.resize(loopCount);
        fs->unsafeDepth = unsafeDepth;
        fs->checked = checked;
        ensureInsertPoint();
    }
}

void CodeGen::emitExprStmt(ExprStmt* s)
{
    Value v = emitExpr(s->expr.get());
    if (!v.isLValue && v.owned)
        holdTemp(v);
    flushTemps(0);
}

static bool implementsDisposable(Type* t)
{
    for (Type* s = t; s && s->isStruct(); s = s->st->base)
        for (Type* i : s->st->interfaces)
            if (i->iface->decl->name == "IDisposable" && i->iface->decl->file->isPrelude)
                return true;
    return false;
}

void CodeGen::emitVarDecl(VarDeclStmt* s)
{
    Type* t = s->type ? declTypeOf(*s->type) : nullptr;
    if (t && t->isVoid())
        err(s->loc, "variable '" + s->name + "' cannot have type 'void'");
    if (s->isConst)
    {
        // a local constant has no storage: its value is computed now and inlined at every use
        if (!isConstantType(t))
            err(s->loc, "constants can only be numbers, bool, char, string or enum values");
        ConstScope sc;
        sc.file = fs->func->file;
        sc.locals = true;
        sc.what = "constant '" + s->name + "'";
        sc.declLoc = s->loc;
        sc.env = &fs->func->env;
        ConstVal cv = constConvert(constEval(s->init.get(), sc), t, s->init->loc);
        ScopeVar& cvar = declareVar(s->name, t, nullptr);
        cvar.ownsArc = false;
        cvar.isConstant = true;
        cvar.constValue = cv;
        return;
    }

    Value init;
    if (s->init)
        init = emitExpr(s->init.get());
    if (!t)
    {
        if (!s->init)
            err(s->loc, "cannot infer the type of '" + s->name + "': 'var' needs an initializer");
        t = init.type;
        if (t->kind == TypeKind::MethodGroup)
        {
            // 'var f = Square;' has the function type of Square if the name has a single meaning.
            t = groupFunctionType(init);
            if (!t)
                err(s->loc, "cannot infer the type of '" + s->name + "' from the function name '" + init.groupName +
                                "' (it is overloaded, generic or not a plain function); declare an Action/Func type");
        }
        if (t->kind == TypeKind::Null || t->kind == TypeKind::ErrorLit || t->isVoid())
            err(s->loc, "cannot infer the type of '" + s->name + "' from '" + t->name + "'");
    }

    if (t->isStruct() && t->st->opaque)
        err(s->loc, "'" + t->name + "' is an incomplete C type and can only be used through a pointer ('" + t->name + "*')");
    llvm::AllocaInst* slot = entryAlloca(llvmTypeOf(t), s->name);
    if (s->init)
    {
        Value cv = convertValue(init, t, s->init->loc);
        builder.CreateStore(consume(cv), slot);
    }
    else
    {
        builder.CreateStore(zeroValue(t), slot);
    }
    flushTemps(0);

    ScopeVar& var = declareVar(s->name, t, slot);
    if (s->isUsing)
    {
        if (!implementsDisposable(t))
            err(s->loc, "'using' requires a struct that implements IDisposable, but '" + t->name + "' does not");
        var.disposable = true;
    }
}

void CodeGen::emitIf(IfStmt* s)
{
    pushScope(); // scope of pattern variables declared in the condition
    Value c = emitCondition(s->cond.get());
    flushTemps(0);

    llvm::BasicBlock* thenBB = newBlock("if.then");
    llvm::BasicBlock* elseBB = s->elseStmt ? newBlock("if.else") : nullptr;
    llvm::BasicBlock* endBB = newBlock("if.end");
    builder.CreateCondBr(c.v, thenBB, elseBB ? elseBB : endBB);

    setBlock(thenBB);
    emitStmt(s->thenStmt.get());
    branchTo(endBB);

    if (elseBB)
    {
        setBlock(elseBB);
        emitStmt(s->elseStmt.get());
        branchTo(endBB);
    }
    setBlock(endBB);
    popScope(true);
}

static bool isLiteralTrue(Expr* e)
{
    return e && e->kind == ExprKind::BoolLit && static_cast<BoolLitExpr*>(e)->value;
}

void CodeGen::emitWhile(WhileStmt* s)
{
    llvm::BasicBlock* condBB = newBlock("while.cond");
    llvm::BasicBlock* bodyBB = newBlock("while.body");
    llvm::BasicBlock* endBB = newBlock("while.end");
    branchTo(condBB);
    setBlock(condBB);
    pushScope(); // pattern variables of the condition live for the whole loop

    if (isLiteralTrue(s->cond.get()))
    {
        builder.CreateBr(bodyBB);
    }
    else
    {
        Value c = emitCondition(s->cond.get());
        flushTemps(0);
        builder.CreateCondBr(c.v, bodyBB, endBB);
    }

    setBlock(bodyBB);
    fs->loops.push_back({endBB, condBB, fs->scopes.size()});
    emitStmt(s->body.get());
    fs->loops.pop_back();
    branchTo(condBB);

    setBlock(endBB);
    popScope(true);
}

void CodeGen::emitDoWhile(DoWhileStmt* s)
{
    llvm::BasicBlock* bodyBB = newBlock("do.body");
    llvm::BasicBlock* condBB = newBlock("do.cond");
    llvm::BasicBlock* endBB = newBlock("do.end");
    branchTo(bodyBB);
    setBlock(bodyBB);
    fs->loops.push_back({endBB, condBB, fs->scopes.size()});
    emitStmt(s->body.get());
    fs->loops.pop_back();
    branchTo(condBB);

    setBlock(condBB);
    Value c = emitCondition(s->cond.get());
    flushTemps(0);
    builder.CreateCondBr(c.v, bodyBB, endBB);
    setBlock(endBB);
}

void CodeGen::emitFor(ForStmt* s)
{
    pushScope();
    if (s->init)
        emitStmt(s->init.get());

    llvm::BasicBlock* condBB = newBlock("for.cond");
    llvm::BasicBlock* bodyBB = newBlock("for.body");
    llvm::BasicBlock* iterBB = newBlock("for.iter");
    llvm::BasicBlock* endBB = newBlock("for.end");
    branchTo(condBB);
    setBlock(condBB);
    if (s->cond && !isLiteralTrue(s->cond.get()))
    {
        Value c = emitCondition(s->cond.get());
        flushTemps(0);
        builder.CreateCondBr(c.v, bodyBB, endBB);
    }
    else
    {
        builder.CreateBr(bodyBB);
    }

    setBlock(bodyBB);
    fs->loops.push_back({endBB, iterBB, fs->scopes.size()});
    emitStmt(s->body.get());
    fs->loops.pop_back();
    branchTo(iterBB);

    setBlock(iterBB);
    for (auto& it : s->iterators)
    {
        Value v = emitExpr(it.get());
        if (!v.isLValue && v.owned)
            holdTemp(v);
        flushTemps(0);
    }
    builder.CreateBr(condBB);

    setBlock(endBB);
    popScope(true);
}

void CodeGen::emitForeach(ForeachStmt* s)
{
    Value it = toRValue(emitExpr(s->iterable.get()));
    Type* collType = it.type;
    if (collType->isStruct())
    {
        emitForeachStruct(s, it);
        return;
    }
    if (!collType->isArray() && !collType->isString())
        err(s->iterable->loc, "'foreach' requires an array, a string or a struct with Count() and Get(int), not '" +
                                  collType->name + "'");
    Type* elemType = collType->isArray() ? collType->elem : types.charTy;

    pushScope(); // holds the collection so that it stays alive during the loop
    auto* ptrTy = llvm::PointerType::getUnqual(ctx);
    llvm::AllocaInst* collSlot = entryAlloca(ptrTy, "foreach.coll");
    builder.CreateStore(consume(it), collSlot);
    declareVar("$foreach", collType, collSlot);
    flushTemps(0);

    llvm::AllocaInst* idxSlot = entryAlloca(builder.getInt64Ty(), "foreach.idx");
    builder.CreateStore(builder.getInt64(0), idxSlot);
    llvm::Value* len = arrayLength(builder.CreateLoad(ptrTy, collSlot));

    llvm::BasicBlock* condBB = newBlock("foreach.cond");
    llvm::BasicBlock* bodyBB = newBlock("foreach.body");
    llvm::BasicBlock* incBB = newBlock("foreach.inc");
    llvm::BasicBlock* endBB = newBlock("foreach.end");
    builder.CreateBr(condBB);

    setBlock(condBB);
    llvm::Value* idx = builder.CreateLoad(builder.getInt64Ty(), idxSlot);
    builder.CreateCondBr(builder.CreateICmpULT(idx, len), bodyBB, endBB);

    setBlock(bodyBB);
    size_t outerDepth = fs->scopes.size();
    pushScope(); // per-iteration scope for the loop variable
    Type* varType = s->type ? declTypeOf(*s->type) : elemType;
    llvm::Value* coll = builder.CreateLoad(ptrTy, collSlot);
    llvm::Value* addr = builder.CreateGEP(llvmTypeOf(elemType), dataPtr(coll), {idx});
    Value elem = Value::lvalue(elemType, addr, true);
    Value cv = convertValue(elem, varType, s->loc);
    llvm::AllocaInst* varSlot = entryAlloca(llvmTypeOf(varType), s->name);
    builder.CreateStore(consume(cv), varSlot);
    declareVar(s->name, varType, varSlot);

    fs->loops.push_back({endBB, incBB, outerDepth});
    emitStmt(s->body.get());
    fs->loops.pop_back();
    popScope(true);
    branchTo(incBB);

    setBlock(incBB);
    builder.CreateStore(builder.CreateAdd(builder.CreateLoad(builder.getInt64Ty(), idxSlot), builder.getInt64(1)), idxSlot);
    builder.CreateBr(condBB);

    setBlock(endBB);
    popScope(true);
}

// foreach over a struct: it must provide "int Count()" and "T Get(int index)" (e.g. List<T>).
void CodeGen::emitForeachStruct(ForeachStmt* s, const Value& it)
{
    Type* collType = it.type;
    SourceLoc loc = s->iterable->loc;
    auto find = [&](const char* name, std::vector<Arg>& probe) {
        std::vector<Candidate> cands = methodCandidates(collType, name);
        if (cands.empty())
            err(loc, "'foreach' over struct '" + collType->name + "' needs the methods 'int Count()' and 'T Get(int index)'");
        return resolveOverload(cands, probe, {}, loc, name);
    };
    std::vector<Arg> noArgs;
    FuncInfo* countFn = find("Count", noArgs);
    Arg probeArg;
    probeArg.v = constInt(types.i32, 0);
    std::vector<Arg> oneArg{probeArg};
    FuncInfo* getFn = find("Get", oneArg);
    if (!countFn->hasThis || !getFn->hasThis || countFn->ret != types.i32 || getFn->ret->isVoid() ||
        getFn->paramTypes[0] != types.i32 || getFn->paramRefs[0] != RefKind::None)
        err(loc, "'foreach' over struct '" + collType->name + "' needs the methods 'int Count()' and 'T Get(int index)'");
    useFunction(*countFn);
    useFunction(*getFn);
    noteCall(*countFn);
    noteCall(*getFn);

    pushScope(); // holds a copy of the struct for the duration of the loop
    llvm::AllocaInst* collSlot = entryAlloca(llvmTypeOf(collType), "foreach.coll");
    builder.CreateStore(consume(it), collSlot);
    declareVar("$foreach", collType, collSlot);
    flushTemps(0);

    llvm::AllocaInst* idxSlot = entryAlloca(builder.getInt32Ty(), "foreach.idx");
    builder.CreateStore(builder.getInt32(0), idxSlot);

    llvm::BasicBlock* condBB = newBlock("foreach.cond");
    llvm::BasicBlock* bodyBB = newBlock("foreach.body");
    llvm::BasicBlock* incBB = newBlock("foreach.inc");
    llvm::BasicBlock* endBB = newBlock("foreach.end");
    builder.CreateBr(condBB);

    setBlock(condBB);
    llvm::Value* idx = builder.CreateLoad(builder.getInt32Ty(), idxSlot);
    llvm::Value* count = builder.CreateCall(countFn->fn, {collSlot});
    builder.CreateCondBr(builder.CreateICmpSLT(idx, count), bodyBB, endBB);

    setBlock(bodyBB);
    size_t outerDepth = fs->scopes.size();
    pushScope();
    Type* elemType = getFn->ret;
    Type* varType = s->type ? declTypeOf(*s->type) : elemType;
    Value elem = Value::rvalue(elemType, builder.CreateCall(getFn->fn, {collSlot, idx}), needsArc(elemType));
    Value cv = convertValue(elem, varType, loc);
    llvm::AllocaInst* varSlot = entryAlloca(llvmTypeOf(varType), s->name);
    builder.CreateStore(consume(cv), varSlot);
    declareVar(s->name, varType, varSlot);

    fs->loops.push_back({endBB, incBB, outerDepth});
    emitStmt(s->body.get());
    fs->loops.pop_back();
    popScope(true);
    branchTo(incBB);

    setBlock(incBB);
    builder.CreateStore(builder.CreateAdd(builder.CreateLoad(builder.getInt32Ty(), idxSlot), builder.getInt32(1)), idxSlot);
    builder.CreateBr(condBB);

    setBlock(endBB);
    popScope(true);
}

void CodeGen::emitSwitch(SwitchStmt* s)
{
    pushScope();
    Value subj = toRValue(emitExpr(s->subject.get()));
    Type* st = subj.type;
    llvm::Value* subjVal = subj.v;
    if (needsArc(st))
    {
        // Keep an owned copy alive for the whole switch.
        llvm::AllocaInst* slot = entryAlloca(llvmTypeOf(st), "switch.subject");
        llvm::Value* owned = consume(subj);
        builder.CreateStore(owned, slot);
        declareVar("$switch", st, slot);
        subjVal = owned;
    }
    flushTemps(0);

    llvm::BasicBlock* endBB = newBlock("switch.end");
    std::vector<llvm::BasicBlock*> bodies;
    for (size_t i = 0; i < s->sections.size(); i += 1)
        bodies.push_back(newBlock("case"));
    llvm::BasicBlock* defaultBB = nullptr;

    for (size_t i = 0; i < s->sections.size(); i += 1)
    {
        for (auto& label : s->sections[i].labels)
        {
            if (label.isDefault)
            {
                if (defaultBB)
                    err(label.loc, "the switch already has a 'default' label");
                defaultBB = bodies[i];
                continue;
            }
            llvm::Value* cond;
            if (label.patType)
            {
                Type* pt = declTypeOf(*label.patType);
                if (pt == st)
                    cond = builder.getTrue(); // "case Error<int> r:" matches the whole result
                else if (st->isResultLike() && st->elem == pt)
                    cond = builder.CreateExtractValue(subjVal, {0});
                else
                    err(label.loc, "pattern type '" + pt->name + "' does not match the switch subject of type '" + st->name + "'");
            }
            else
            {
                Value lv = emitRValue(label.value.get());
                cond = emitCompare(BinOp::Eq, Value::rvalue(st, subjVal), lv, label.loc).v;
                flushTemps(0);
            }
            llvm::BasicBlock* next = newBlock("case.test");
            builder.CreateCondBr(cond, bodies[i], next);
            setBlock(next);
        }
    }
    branchTo(defaultBB ? defaultBB : endBB);

    fs->loops.push_back({endBB, nullptr, fs->scopes.size()});
    for (size_t i = 0; i < s->sections.size(); i += 1)
    {
        SwitchSection& sec = s->sections[i];
        setBlock(bodies[i]);
        pushScope();
        for (auto& label : sec.labels)
        {
            if (!label.patType || label.patName.empty())
                continue;
            Type* pt = declTypeOf(*label.patType);
            llvm::AllocaInst* slot = entryAlloca(llvmTypeOf(pt), label.patName);
            llvm::Value* payload = pt == st ? subjVal : builder.CreateExtractValue(subjVal, {1});
            emitRetainValue(pt, payload);
            builder.CreateStore(payload, slot);
            declareVar(label.patName, pt, slot);
            break;
        }
        for (auto& stmt : sec.body)
            emitStmt(stmt.get());
        if (reachable())
            diag.error(sec.loc, "control cannot fall through from one case label to another (missing 'break')");
        popScope(true);
    }
    fs->loops.pop_back();

    setBlock(endBB);
    popScope(true);
}

void CodeGen::emitBreakContinue(bool isBreak, SourceLoc loc)
{
    for (size_t i = fs->loops.size(); i > 0; i -= 1)
    {
        LoopCtx& l = fs->loops[i - 1];
        if (!isBreak && !l.continueBB)
            continue;
        emitCleanupsDownTo(l.scopeDepth);
        builder.CreateBr(isBreak ? l.breakBB : l.continueBB);
        return;
    }
    err(loc, isBreak ? "'break' is only allowed inside a loop or switch" : "'continue' is only allowed inside a loop");
}

void CodeGen::emitReturn(ReturnStmt* s)
{
    Type* rt = fs->retType;
    if (s->value)
    {
        if (rt->isVoid())
            err(s->loc, "a void function cannot return a value");
        Value v = emitExpr(s->value.get());
        Value cv = convertValue(v, rt, s->value->loc);
        llvm::Value* rv = consume(cv);
        flushTemps(0);
        emitCleanupsDownTo(0);
        builder.CreateRet(rv);
        return;
    }
    if (isVoidResult(rt))
    {
        // "return;" in an Error<void> function reports success.
        emitCleanupsDownTo(0);
        builder.CreateRet(makeSome(rt, nullptr));
        return;
    }
    if (!rt->isVoid())
        err(s->loc, "a return value of type '" + rt->name + "' is required");
    emitCleanupsDownTo(0);
    builder.CreateRetVoid();
}

void CodeGen::emitUsingBlock(UsingBlockStmt* s)
{
    pushScope();
    emitVarDecl(s->decl.get());
    emitStmt(s->body.get());
    popScope(true);
}
