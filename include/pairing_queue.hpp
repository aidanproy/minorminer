#pragma once
#include <map>
#include <set>
#include <string>
#include <vector>

#include <iso646.h>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <vector>

#include "debug.hpp"
#include "util.hpp"

// Macros local to this file, undefined at the end
#define max_P (numeric_limits<P>::max())

namespace pairing_queue {
// Import std library components
using std::vector;
using std::fill;
using std::numeric_limits;

template <typename P>
struct plain_node {
    P val;
    plain_node<P> *next, *desc, *prev;
    inline bool operator<(const plain_node<P> &b) const { return (val < b.val) || ((val == b.val) && (this < &b)); }
};

template <typename P>
struct time_node {
    P val;
    time_node<P> *next, *desc, *prev;
    int time;
    inline bool operator<(const time_node<P> &b) const { return (val < b.val) || ((val == b.val) && (this < &b)); }
};

//! A priority queue based on a pairing heap, with fixed memory footprint and support for a decrease-key operation
template <typename P, typename N = plain_node<P>>
class pairing_queue {
  public:
    typedef P value_type;

  protected:
    vector<N> nodes;

    N *root;

  public:
    pairing_queue(int n) : nodes(n), root(nullptr) {}

    //! Reset the queue and fill the values with a default
    inline void reset_fill(const P v) {
        root = nullptr;
        for (auto &n : nodes) {
            reset(&n, v);
        }
    }

    inline bool has(int k) const { return 0 <= k && k < nodes.size(); }

    //! Reset the queue and set the default to the maximum value
    inline void reset() { reset_fill(max_P); }

  protected:
    inline void reset(N *n) {
        minorminer_assert(!empty(n));
        n->desc = nullptr;
        n->next = nullptr;
        n->prev = n;
    }

    inline void reset(N *n, P v) {
        reset(n);
        n->val = v;
    }

  public:
    //! Remove the minimum value
    //! return true if any change is made
    inline bool delete_min() {
        if (empty()) return false;

        N *newroot = root->desc;
        if (!empty(newroot)) {
            newroot = merge_pairs(newroot);
            newroot->prev = nullptr;
            newroot->next = nullptr;
        }
        reset(root);
        root = newroot;
        return true;
    }

    //! Remove and return (in args) the minimum key, value pair
    inline bool pop_min(int &key, P &value) {
        if (empty()) {
            return false;
        }
        key = min_key();
        value = min_value();
        delete_min();
        return true;
    }

  public:
    //! Decrease the value of k to v
    //! NOTE: Assumes that v is lower than the current value of k
    inline void decrease_value(int k, const P &v) { decrease_value(node(k), v); }

  protected:
    inline void decrease_value(N *n, const P &v) {
        minorminer_assert(!empty(n));
        minorminer_assert(v < n->val);

        n->val = v;
        decrease(n);
    }

  public:
    //! Decrease the value of k to v
    //! Does nothing if v isn't actually a decrease.
    inline bool check_decrease_value(int k, const P &v) { return check_decrease_value(node(k), v); }

  protected:
    inline bool check_decrease_value(N *n, const P &v) {
        minorminer_assert(!empty(n));
        if (v < n->val) {
            n->val = v;
            decrease(n);
            return true;
        } else {
            return false;
        }
    }

  public:
    inline void set_value(int k, const P &v) { set_value(node(k), v); }

  protected:
    inline void set_value(N *n, const P &v) {
        minorminer_assert(!empty(n));
        if (n->prev == n) {
            n->val = v;
            root = merge_roots(n, root);
        } else if (v < n->val) {
            n->val = v;
            decrease(n);
        } else if (n->val < v) {
            n->val = v;
            remove(n);
            root = merge_roots(n, root);
        }
    }

  public:
    inline void set_value_unsafe(int k, const P &v) { set_value_unsafe(node(k), v); }

  protected:
    inline void set_value_unsafe(N *n, const P &v) {
        minorminer_assert(!empty(n));
        n->val = v;
    }

  public:
    inline P min_value() const {
        minorminer_assert(!empty());
        return root->val;
    }

    inline int min_key() const {
        minorminer_assert(!empty());
        return key(root);
    }

  protected:
    inline int key(N *n) const { return n - nodes.data(); }

  public:
    inline bool empty(void) const { return empty(root); }

  protected:
    inline bool empty(N *n) const { return n == nullptr; }

  public:
    inline P value(int k) const { return const_node(k)->val; }

  protected:
    inline void checkbound(const int k) const { minorminer_assert(has(k)); }

    inline N *node(int k) {
        checkbound(k);
        return nodes.data() + k;
    }

    inline const N *const_node(int k) const {
        checkbound(k);
        return nodes.data() + k;
    }

    inline N *merge_roots(N *a, N *b) {
        // even this version of merge_roots is slightly unsafe -- we never call it with a null, so let's not check!
        // * doesn't check for nullval
        minorminer_assert(!empty(a));

        if (empty(b)) return a;
        N *c = merge_roots_unsafe(a, b);
        c->prev = nullptr;
        return c;
    }

    inline N *merge_roots_unsafe(N *a, N *b) {
        // this unsafe version of merge_roots which
        // * doesn't check for nullval
        // * doesn't ensure that the returned node has prev[a] = nullval
        minorminer_assert(!empty(a));
        minorminer_assert(!empty(b));

        if (*a < *b)
            return merge_roots_unchecked(a, b);
        else
            return merge_roots_unchecked(b, a);
    }

    inline N *merge_roots_unchecked(N *a, N *b) {
        // this very unsafe version of self.merge_roots which
        // * doesn't check for nullval
        // * doesn't ensure that the returned node has prev[a] = nullval
        // * doesn't check that a < b
        minorminer_assert(!empty(a));
        minorminer_assert(!empty(b));
        // minorminer_assert(a < b);

        N *c = b->next = a->desc;
        if (!empty(c)) c->prev = b;
        b->prev = a;
        a->desc = b;
        return a;
    }

    inline N *merge_pairs(N *a) {
        if (empty(a)) return nullptr;
        N *r = nullptr;
        do {
            N *b = a->next;
            if (!empty(b)) {
                N *c = b->next;
                b = merge_roots_unsafe(a, b);
                b->prev = r;
                r = b;
                a = c;
            } else {
                a->prev = r;
                r = a;
                break;
            }
        } while (!empty(a));
        a = r;
        r = a->prev;
        while (!empty(r)) {
            N *t = r->prev;
            a = merge_roots_unsafe(a, r);
            r = t;
        }
        return a;
    }

    inline void remove(N *a) {
        minorminer_assert(!empty(a));
        N *b = a->prev;
        N *c = a->next;
        minorminer_assert(!empty(b));
        if (b->desc == a)
            b->desc = c;
        else
            b->next = c;

        if (!empty(c)) {
            c->prev = b;
            a->next = nullptr;
        }
    }

    inline void decrease(N *a) {
        minorminer_assert(!empty(a));
        if (!empty(a->prev)) {
            minorminer_assert(a != root);  // theoretically, root is the only node with empty(prev)
            remove(a);
            root = merge_roots(a, root);
        }
    }
};

//! This is a specialization of the pairing_queue that has a constant time
//! reset method, at the expense of an extra check when values are set or updated.
template <typename P, typename N = time_node<P>>
class pairing_queue_fast_reset : public pairing_queue<P, N> {
    using super = pairing_queue<P, N>;

  protected:
    int now;

    inline void reset(N *n) {
        super::reset(n);
        n->time = now;
    }

    inline bool current(N *n) {
        if (n->time != now) {
            reset(n);
            return false;
        }
        return true;
    }

  public:
    pairing_queue_fast_reset(int n) : super(n), now(0) {}

    inline void reset() {
        super::root = nullptr;
        if (!now++) {
            for (auto &n : super::nodes) n.time = 0;
        }
    }

    inline void set_value_unsafe(int k, const P &v) {
        auto n = super::node(k);
        current(n);
        super::set_value_unsafe(n, v);
    }

    inline void set_value(int k, const P &v) {
        auto n = super::node(k);
        if (current(n))
            super::set_value(n, v);
        else {
            n->val = v;
            super::root = super::merge_roots(n, super::root);
        }
    }

    inline bool check_decrease_value(int k, const P &v) {
        auto n = super::node(k);
        if (current(n))
            return super::check_decrease_value(n, v);
        else {
            super::set_value(n, v);
            return true;
        }
    }

    inline P get_value(int k) const {
        auto n = super::const_node(k);
        if (n->time == now)
            return n->val;
        else
            return max_P;
    }
};
#undef nullval
#undef max_P
}
