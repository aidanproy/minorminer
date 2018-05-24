"""
minorminer is a tool for finding graph minor embeddings, developed to embed Ising problems onto quantum annealers (QA). While it can be used to find minors in arbitrary graphs, it is particularly geared towards the state of the art in QA: problem graphs of a few to a few hundred variables, and hardware graphs of a few thousand qubits.

The primary function :py:func:`find_embedding` is a modernized implementation of the Cai, Macready and Roy [1] algorithm with several new features to give users finer control and address a wider class of problems.

Definitions
===========

Let :math:`S` and :math:`T` be graphs, which we call source and target.  If a set of target nodes is either size 1 or it's a connected subgraph of :math:`T`, we call it a chain.  A mapping :math:`f` from source nodes to chains is an embedding of :math:`S` into :math:`T` when

- for every pair of nodes :math:`s_1 \\neq s_2` of :math:`S`, the chains :math:`f(s_1)` and :math:`f(s_2)` are disjoint, and
- for every source edge :math:`(s_1, s_2)`, there is at least one target edge :math:`(s_1, s_2)` for which :math:`t_1 \\in f(s_1)` and :math:`t_2 \\in f(s_2)`

In the case that two chains are not disjoint, we say that they overlap.  If a mapping has overlapping chains, and some of its source edges are represented by qubits shared by their associated chains but the others are all proper, then we call that mapping an overlapped embedding.

Higher-level Algorithm Description
==================================

This is a very rough description of the heuristic more properly described in [1], and most accurately described in the source.

Where it is difficult to find proper embeddings, it is much easier to find embeddings where the chains are allowed to overlap.  The key operation is a placement heuristic.  We initialize by setting :math:`f(s_0) = {t_0}` for chosen source and target nodes, and then proceed placing nodes heedless of the overlaps that accumulate.  We persist: tear out a chain, clean up its neighboring chains, and replace it.  The placement heuristic attempts to avoid the qubits involved in overlaps, and once it finds an embedding, continues in the same fashion with the aim of minimizing the sizes of the chains.

Placement Heuristic
-------------------

Let :math:`s` be a source node with neighbors :math:`n_1, \cdots, n_d`.  We first measure the distance from each neighbor's chain, :math:`f(n_i)` to all target nodes.  Then, we select a target node :math:`t_0` that minimizes the sum of distances to those chains.  Then, we follow a minimum-length path from :math:`t_0` to each neighbor's chain, and the union of those paths is the new chain for :math:`s`.  The distances are computed in :math:`T` as a node-weighted graph, where the weight of a node is an exponential function of the number of chains which use it.


Hinting and Constraining
========================

New features to this implementation are ``initial_chains``, ``fixed_chains``, and ``restrict_chains``.  Initial chains are used during the initialization procedure, and can be used to provide hints in the form of an overlapped, partial, or otherwise faulty embedding.  Fixed chains are held constant during the execution of the algorithm.  Finally, chains can be restricted to being contained within a user-defined subset of :math:`T` -- this constraint is somewhat soft, and the algorithm can be expected to violate it.

[1] https://arxiv.org/abs/1406.2741
"""
include "minorminer.pxi"
import os

def find_embedding(S, T, **params):
    """
    find_embedding(S, T, **params)
    Heuristically attempt to find a minor-embedding of a graph representing an Ising/QUBO into a target graph.

    Args:

        S: an iterable of label pairs representing the edges in the source graph

        T: an iterable of label pairs representing the edges in the target graph

        **params (optional): see below

    Returns:

        When return_overlap = False (the default), returns a dict that maps labels in S to lists of labels in T

        When return_overlap = True, returns a tuple consisting of a dict that maps labels in S to lists of labels in T and a bool indicating whether or not a valid embedding was foun

        When interrupted by Ctrl-C, returns the best embedding found so far

        Note that failure to return an embedding does not prove that no embedding exists

    Optional parameters::

        max_no_improvement: Maximum number of failed iterations to improve the
            current solution, where each iteration attempts to find an embedding
            for each variable of S such that it is adjacent to all its
            neighbours. Integer >= 0 (default = 10)

        random_seed: Seed for the random number generator that find_embedding
            uses. Integer >=0 (default is randomly set)

        timeout: Algorithm gives up after timeout seconds. Number >= 0 (default
            is approximately 1000 seconds, stored as a double)

        max_beta: Qubits are assigned weight according to a formula (beta^n)
            where n is the number of chains containint that qubit.  This value
            should never be less than or equal to 1. (default is effectively
            infinite, stored as a double)

        tries: Number of restart attempts before the algorithm stops. On
            D-WAVE 2000Q, a typical restart takes between 1 and 60 seconds.
            Integer >= 0 (default = 10)

        inner_rounds: the algorithm takes at most this many iterations between
            restart attempts; restart attempts are typically terminated due to
            max_no_improvement. Integer >= 0 (default = effectively infinite)

        chainlength_patience: Maximum number of failed iterations to improve
            chainlengths in the current solution, where each iteration attempts
            to find an embedding for each variable of S such that it is adjacent
            to all its neighbours. Integer >= 0 (default = 10)

        max_fill: Restricts the number of chains that can simultaneously
            incorporate the same qubit during the search. Integer >= 0, values
            above 63 are treated as 63 (default = effectively infinite)

        threads: Maximum number of threads to use. Note that the
            parallelization is only advantageous where the expected degree of
            variables is significantly greater than the number of threads.
            Integer >= 1 (default = 1)

        return_overlap: This function returns an embedding whether or not qubits
            are used by multiple variables. Set this value to 1 to capture both
            return values to determine whether or not the returned embedding is
            valid. Logical 0/1 integer (default = 0)

        skip_initialization: Skip the initialization pass. Note that this only
            works if the chains passed in through initial_chains and
            fixed_chains are semi-valid. A semi-valid embedding is a collection
            of chains such that every adjacent pair of variables (u,v) has a
            coupler (p,q) in the hardware graph where p is in chain(u) and q is
            in chain(v). This can be used on a valid embedding to immediately
            skip to the chainlength improvement phase. Another good source of
            semi-valid embeddings is the output of this function with the
            return_overlap parameter enabled. Logical 0/1 integer (default = 0)

        verbose: Level of output verbosity. Integer < 4 (default = 0).
            When set to 0, the output is quiet until the final result.
            When set to 1, output looks like this:

                initialized
                max qubit fill 3; num maxfull qubits=3
                embedding trial 1
                max qubit fill 2; num maxfull qubits=21
                embedding trial 2
                embedding trial 3
                embedding trial 4
                embedding trial 5
                embedding found.
                max chain length 4; num max chains=1
                reducing chain lengths
                max chain length 3; num max chains=5

            When set to 2, outputs the information for lower levels and also
                reports progress on minor statistics (when searching for an
                embedding, this is when the number of maxfull qubits decreases;
                when improving, this is when the number of max chains decreases)
            When set to 3, report before each before each pass. Look here when
                tweaking `tries`, `inner_rounds`, and `chainlength_patience`
            When set to 4, report additional debugging information. By default,
                this package is built without this functionality. In the c++
                headers, this is controlled by the CPPDEBUG flag
            Detailed explanation of the output information:
                max qubit fill: largest number of variables represented in a qubit
                num maxfull: the number of qubits that has max overfill
                max chain length: largest number of qubits representing a single variable
                num max chains: the number of variables that has max chain size

        initial_chains: Initial chains inserted into an embedding before
            fixed_chains are placed, which occurs before the initialization
            pass. These can be used to restart the algorithm in a similar state
            to a previous embedding; for example, to improve chainlength of a
            valid embedding or to reduce overlap in a semi-valid embedding (see
            skip_initialization) previously returned by the algorithm. Missing
            or empty entries are ignored. A dictionary, where initial_chains[i]
            is a list of qubit labels.

        fixed_chains: Fixed chains inserted into an embedding before the
            initialization pass. As the algorithm proceeds, these chains are not
            allowed to change. Missing or empty entries are ignored. A
            dictionary, where fixed_chains[i] is a list of qubit labels.

        restrict_chains: Throughout the algorithm, we maintain the condition
            that chain[i] is a subset of restrict_chains[i] for each i, except
            those with missing or empty entries. A dictionary, where
            restrict_chains[i] is a list of qubit labels.

        suspend_chains: This is a metafeature that is only implemented in the Python
            interface.  suspend_chains[i] is an iterable of iterables; for example
                suspend_chains[i] = [blob_1, blob_2],
            with each blob_j an iterable of target node labels.
            this enforces the following:
                for each suspended variable i,
                    for each blob_j in the suspension of i,
                        at least one qubit from blob_j will be contained in the
                        chain for i

            we accomplish this trhough the following problem transformation
            for each iterable blob_j in suspend_chains[i], 
                * add an auxiliary node Zij to both source and target graphs
                * set fixed_chains[Zij] = [Zij]
                * add the edge (i,Zij) to the source graph
                * add the edges (q,Zij) to the target graph for each q in blob_j
    """
    cdef _input_parser _in
    _in = _input_parser(S, T, params)

    cdef vector[int] chain
    cdef vector[vector[int]] chains
    cdef int success = findEmbedding(_in.Sg, _in.Tg, _in.opts, chains)

    cdef int nc = chains.size()

    rchain = {}
    if chains.size():
        for v in range(nc-_in.pincount):
            chain = chains[v]
            rchain[_in.SL.label(v)] = [_in.TL.label(z) for z in chain]

    if _in.opts.return_overlap:
        return rchain, success
    else:
        return rchain

cdef class _input_parser:
    cdef input_graph Sg, Tg
    cdef labeldict SL, TL
    cdef optional_parameters opts
    cdef int pincount
    def __init__(self, S, T, params):
        cdef uint64_t *seed
        cdef vector[int] chain

        self.opts.localInteractionPtr.reset(new LocalInteractionPython())

        names = {"max_no_improvement", "random_seed", "timeout", "tries", "verbose",
                 "fixed_chains", "initial_chains", "max_fill", "chainlength_patience",
                 "return_overlap", "skip_initialization", "inner_rounds", "threads",
                 "restrict_chains", "suspend_chains", "max_beta"}

        for name in params:
            if name not in names:
                raise ValueError("%s is not a valid parameter for find_embedding"%name)

        try: self.opts.max_no_improvement = int( params["max_no_improvement"] )
        except KeyError: pass

        try: self.opts.skip_initialization = int( params["skip_initialization"] )
        except KeyError: pass

        try: self.opts.chainlength_patience = int( params["chainlength_patience"] )
        except KeyError: pass

        try: self.opts.seed( long(params["random_seed"]) )
        except KeyError:
            seed_obj = os.urandom(sizeof(uint64_t))
            seed = <uint64_t *>(<void *>(<uint8_t *>(seed_obj)))
            self.opts.seed(seed[0])

        try: self.opts.tries = int(params["tries"])
        except KeyError: pass

        try: self.opts.verbose = int(params["verbose"])
        except KeyError: pass

        try: self.opts.inner_rounds = int(params["inner_rounds"])
        except KeyError: pass

        try: self.opts.timeout = float(params["timeout"])
        except KeyError: pass

        try: self.opts.max_beta = float(params["max_beta"])
        except KeyError: pass

        try: self.opts.return_overlap = int(params["return_overlap"])
        except KeyError: pass

        try: self.opts.max_fill = int(params["max_fill"])
        except KeyError: pass

        try: self.opts.threads = int(params["threads"])
        except KeyError: pass

        self.SL = _read_graph(self.Sg, S)
        self.TL = _read_graph(self.Tg, T)

        cdef int checkT = len(self.TL)
        cdef int checkS = len(self.SL)

        pincount = 0
        cdef int nonempty
        cdef dict fixed_chains = params.get("fixed_chains", {})
        if "suspend_chains" in params:
            suspend_chains = params["suspend_chains"]
            for v, blobs in suspend_chains.items():
                for i,blob in enumerate(blobs):
                    nonempty = 0
                    pin = "__MINORMINER_INTERNAL_PIN_FOR_SUSPENSION", v, i
                    if pin in self.SL:
                        raise ValueError("node label %s is a special value used by the suspend_chains feature; please relabel your source graph"%(pin,))
                    if pin in self.TL:
                        raise ValueError("node label %s is a special value used by the suspend_chains feature; please relabel your target graph"%(pin,))

                    for q in blob:
                        self.Tg.push_back(self.TL[pin], self.TL[q])
                        nonempty = 1
                    if nonempty:
                        pincount += 1
                        fixed_chains[pin] = [pin]
                        self.Sg.push_back(self.SL[v], self.SL[pin])

        if checkS+pincount < len(self.SL):
            raise RuntimeError("suspend_chains use source node labels that weren't referred to by any edges")
        if checkT+pincount < len(self.TL):
            raise RuntimeError("suspend_chains use target node labels that weren't referred to by any edges")

        checkS += pincount
        checkT += pincount
        
        _get_chainmap(fixed_chains, self.opts.fixed_chains, self.SL, self.TL)
        if checkS < len(self.SL):
            raise RuntimeError("fixed_chains use source node labels that weren't referred to by any edges")
        if checkT < len(self.TL):
            raise RuntimeError("fixed_chains use target node labels that weren't referred to by any edges")
        _get_chainmap(params.get("initial_chains",[]), self.opts.initial_chains, self.SL, self.TL)
        if checkS < len(self.SL):
            raise RuntimeError("initial_chains use source node labels that weren't referred to by any edges")
        if checkT < len(self.TL):
            raise RuntimeError("initial_chains use target node labels that weren't referred to by any edges")
        _get_chainmap(params.get("restrict_chains",[]), self.opts.restrict_chains, self.SL, self.TL)
        if checkS < len(self.SL):
            raise RuntimeError("restrict_chains use source node labels that weren't referred to by any edges")
        if checkT < len(self.TL):
            raise RuntimeError("restrict_chains use target node labels that weren't referred to by any edges")        


cdef class minorminer:
    cdef _input_parser _in
    cdef pathfinder_wrapper *pf
    def __cinit__(self, S, T, **params):
        self._in = _input_parser(S, T, params)
        self.pf = new pathfinder_wrapper(self._in.Sg, self._in.Tg, self._in.opts)

    def __dealloc__(self):
        del self.pf   

    def find_embedding(self):
        cdef int i, success = self.pf.heuristicEmbedding()
        cdef vector[int] chain

        rchain = {}
        if self._in.opts.return_overlap or success:
            for v in range(self.pf.num_vars()-self._in.pincount):
                chain.clear()
                self.pf.get_chain(v, chain)
                rchain[self._in.SL.label(v)] = [self._in.TL.label(z) for z in chain]

        if self._in.opts.return_overlap:
            return rchain, success
        else:
            return rchain

    def find_embeddings(self, int n, int force = 0):
        embs = []

        while n > 0:
            emb = self.find_embedding()
            if isinstance(emb, tuple):
                emb = emb[0]
                succ = 1
            else:
                succ = len(emb)
            if succ:
                embs.append(emb)
            if succ or not force:
                n -= 1
        return embs

    def improve_embeddings(self, list embs):
        cdef chainmap c = chainmap()
        cdef int n = len(embs)
        cdef list _embs = []
        for i in range(len(embs)):
            _get_chainmap(embs[i], c, self._in.SL, self._in.TL)
            self.pf.set_initial_chains(c)
            emb = self.find_embedding()
            if isinstance(emb, tuple):
                emb = emb[0]
            _embs.append(emb)
        return _embs

    cdef dict count_overlaps(self, list chains):
        cdef dict o = {}
        for chain in chains:
            for q in chain:
                o[q] = 1+o.get(q,-1)
        return o

    cdef list histogram_key(self, list sizes):
        cdef dict h = {}
        cdef int s, x
        cdef tuple t
        for s in sizes:
            if s:
                h[s] = 1+h.get(s, 0)

        return [t[i] for t in sorted(h.items(), reverse = True) for i in (0,1)]

    def quality_key(self, emb, embedded = False):
        cdef int state = 2
        cdef dict o
        cdef list L, O
        if emb == {}:
            return (state,)

        state = 0
        L = self.histogram_key([len(c) for c in emb.values()])

        if embedded:
            O = []
        else:
            o = self.count_overlaps(emb.values())
            O = self.histogram_key(o.values())
            if len(O):
                state = 1

        return (state, O, L)


cdef int _get_chainmap(C, chainmap &CMap, SL, TL) except -1:
    cdef vector[int] chain
    CMap.clear();
    try:
        for a in C:
            chain.clear()
            if C[a]:
                if TL is None:
                    for x in C[a]:
                        chain.push_back(<int> x)
                else:
                    for x in C[a]:
                        chain.push_back(<int> TL[x])
                if SL is None:
                    CMap.insert(pair[int,vector[int]](a, chain))
                else:
                    CMap.insert(pair[int,vector[int]](SL[a], chain))

    except (TypeError, ValueError):
        try:
            nc = next(C)
        except:
            nc = None
        if nc is None:
            raise ValueError("initial_chains and fixed_chains must be mappings (dict-like) from ints to iterables of ints; C has type %s and I can't iterate over it"%type(C))
        else:
            raise ValueError("initial_chains and fixed_chains must be mappings (dict-like) from ints to iterables of ints; C has type %s and next(C) has type %s"%(type(C), type(nc)))

cdef _read_graph(input_graph &g, E):
    cdef labeldict L = labeldict()
    for a,b in E:
        g.push_back(L[a],L[b])
    return L

__all__ = ["find_embedding"]
