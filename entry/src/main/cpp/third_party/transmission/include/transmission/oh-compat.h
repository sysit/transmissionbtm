// oh-compat.h — C++20 compatibility shims for OH NDK clang 15.0.4 libc++
//
// OH NDK's libc++ is pre-LLVM 16 and lacks most std::ranges algorithms,
// std::views, and std::lexicographical_compare_three_way.
//
// Force-included (-include) during cross-compilation. All symbols are in
// namespace ::tr. A pre-build Python script replaces std::ranges::X → tr::X
// and std::views::X → tr::X_of in the transmission source tree.
//
// Guarded to C++20 only — CMake compiler detection passes -include for all
// translation units, including C and pre-C++20 test compilations.
//
#pragma once

#if defined(__cplusplus) && __cplusplus >= 202002L

#include <algorithm>
#include <compare>
#include <iterator>
#include <type_traits>
#include <functional>

namespace tr {

// ═══════════════════════════════════════════════════════════════════════
// MACRO: generate a simple range→iter wrapper for any std:: algorithm
// that takes (first, last, args...) and has a ranges:: counterpart with
// (range, args...)
// ═══════════════════════════════════════════════════════════════════════

#define TR_DEFINE_RANGE_ALG_0(name)                                          \
    template <typename R>                                                    \
    constexpr auto name(R&& r)                                               \
    {                                                                        \
        return std::name(std::begin(r), std::end(r));                        \
    }

#define TR_DEFINE_RANGE_ALG_1(name)                                          \
    template <typename R, typename A1>                                       \
    constexpr auto name(R&& r, A1&& a1)                                      \
    {                                                                        \
        return std::name(std::begin(r), std::end(r), std::forward<A1>(a1));  \
    }

#define TR_DEFINE_RANGE_ALG_2(name)                                          \
    template <typename R, typename A1, typename A2>                          \
    constexpr auto name(R&& r, A1&& a1, A2&& a2)                             \
    {                                                                        \
        return std::name(std::begin(r), std::end(r),                         \
                         std::forward<A1>(a1), std::forward<A2>(a2));        \
    }

#define TR_DEFINE_RANGE_ALG_3(name)                                          \
    template <typename R, typename A1, typename A2, typename A3>             \
    constexpr auto name(R&& r, A1&& a1, A2&& a2, A3&& a3)                    \
    {                                                                        \
        return std::name(std::begin(r), std::end(r),                         \
                         std::forward<A1>(a1), std::forward<A2>(a2),         \
                         std::forward<A3>(a3));                              \
    }

// ═══════════════════════════════════════════════════════════════════════
// Simple subrange replacement — std::ranges::subrange doesn't exist in OH libc++
// ═══════════════════════════════════════════════════════════════════════

template <typename I>
struct subrange
{
    I begin_;
    I end_;

    subrange() = default;
    subrange(I begin, I end) : begin_(begin), end_(end) {}

    [[nodiscard]] constexpr auto begin() const { return begin_; }
    [[nodiscard]] constexpr auto end()   const { return end_; }
    [[nodiscard]] constexpr bool empty() const { return begin_ == end_; }
    [[nodiscard]] constexpr auto front() const { return *begin_; }
    [[nodiscard]] constexpr auto back()  const { return *std::prev(end_); }
    [[nodiscard]] constexpr auto size()  const { return (size_t)(end_ - begin_); }
};

// ---- Simple 0-arg wrappers ----
TR_DEFINE_RANGE_ALG_0(adjacent_find)
TR_DEFINE_RANGE_ALG_1(adjacent_find)  // with binary predicate
TR_DEFINE_RANGE_ALG_0(max_element)
TR_DEFINE_RANGE_ALG_1(max_element)    // with comparator

// ---- Simple 1-arg wrappers ----
TR_DEFINE_RANGE_ALG_1(count_if)
TR_DEFINE_RANGE_ALG_1(for_each)
TR_DEFINE_RANGE_ALG_1(shuffle)

// ---- all_of / any_of / none_of — need both range+pred and iter+iter+pred overloads ----
#define TR_DEFINE_RANGE_PRED_ALG(name)                                         \
    template <typename R, typename Pred>                                       \
    constexpr auto name(R&& r, Pred pred)                                      \
    {                                                                          \
        return std::name(std::begin(r), std::end(r), pred);                    \
    }                                                                          \
    template <typename I, typename S, typename Pred>                           \
    constexpr auto name(I first, S last, Pred pred)                            \
    {                                                                          \
        return std::name(first, last, pred);                                   \
    }
TR_DEFINE_RANGE_PRED_ALG(all_of)
TR_DEFINE_RANGE_PRED_ALG(any_of)
TR_DEFINE_RANGE_PRED_ALG(none_of)
TR_DEFINE_RANGE_PRED_ALG(find_if_not)
#undef TR_DEFINE_RANGE_PRED_ALG

// ---- partition / stable_partition — return subrange {partition_point, end} ----
template <typename R, typename Pred>
constexpr auto partition(R&& r, Pred pred)
{
    auto first = std::begin(r);
    auto last  = std::end(r);
    return tr::subrange<decltype(first)>{std::partition(first, last, pred), last};
}

template <typename R, typename Pred>
constexpr auto stable_partition(R&& r, Pred pred)
{
    auto first = std::begin(r);
    auto last  = std::end(r);
    return tr::subrange<decltype(first)>{std::stable_partition(first, last, pred), last};
}

// ---- Simple 2-arg wrappers ----
TR_DEFINE_RANGE_ALG_2(copy_if)

// ---- Special: find/binary_search/find_if — 1 value arg but second is const ref
template <typename R, typename T>
constexpr auto find(R&& r, T const& val)
{
    return std::find(std::begin(r), std::end(r), val);
}

template <typename R, typename Pred>
constexpr auto find_if(R&& r, Pred pred)
{
    return std::find_if(std::begin(r), std::end(r), pred);
}

template <typename R, typename T>
constexpr bool binary_search(R&& r, T const& val)
{
    return std::binary_search(std::begin(r), std::end(r), val);
}

// ---- sort (range overloads) ----
template <typename R>
constexpr void sort(R&& r)
{
    std::sort(std::begin(r), std::end(r));
}

template <typename R, typename Comp>
constexpr void sort(R&& r, Comp comp)
{
    std::sort(std::begin(r), std::end(r), comp);
}

// ---- Special: partial_sort — r.middle passed as iterator, not range ----
template <typename R, typename I>
constexpr void partial_sort(R&& r, I middle)
{
    std::partial_sort(std::begin(r), middle, std::end(r));
}

template <typename R, typename I, typename Comp>
constexpr void partial_sort(R&& r, I middle, Comp comp)
{
    std::partial_sort(std::begin(r), middle, std::end(r), comp);
}

// ---- Special: partial_sort_copy — two range args ----
template <typename InR, typename OutR>
constexpr auto partial_sort_copy(InR&& in, OutR&& out)
{
    return std::partial_sort_copy(std::begin(in), std::end(in),
                                   std::begin(out), std::end(out));
}

template <typename InR, typename OutR, typename Comp>
constexpr auto partial_sort_copy(InR&& in, OutR&& out, Comp comp)
{
    return std::partial_sort_copy(std::begin(in), std::end(in),
                                   std::begin(out), std::end(out), comp);
}

// ---- Special: equal_range — returns subrange (not pair) for .empty()/.front() compatibility ----
template <typename R, typename T>
constexpr auto equal_range(R&& r, T const& val)
{
    auto first = std::begin(r);
    auto last  = std::end(r);
    auto p = std::equal_range(first, last, val);
    return tr::subrange<decltype(first)>{p.first, p.second};
}

template <typename R, typename T, typename Comp>
constexpr auto equal_range(R&& r, T const& val, Comp comp)
{
    auto first = std::begin(r);
    auto last  = std::end(r);
    auto p = std::equal_range(first, last, val, comp);
    return tr::subrange<decltype(first)>{p.first, p.second};
}

// ---- Special: lower_bound — value arg ----
template <typename R, typename T>
constexpr auto lower_bound(R&& r, T const& val)
{
    return std::lower_bound(std::begin(r), std::end(r), val);
}

template <typename R, typename T, typename Comp>
constexpr auto lower_bound(R&& r, T const& val, Comp comp)
{
    return std::lower_bound(std::begin(r), std::end(r), val, comp);
}

template <typename R, typename T, typename Comp, typename Proj>
constexpr auto lower_bound(R&& r, T const& val, Comp comp, Proj proj)
{
    return std::lower_bound(std::begin(r), std::end(r), val,
                            [&](auto const& a, auto const& b) { return comp(proj(a), b); });
}

// ---- Special: search — returns subrange (pair) for structured binding compatibility ----
template <typename R, typename PatR>
constexpr auto search(R&& r, PatR&& pat)
{
    auto first = std::begin(r);
    auto last  = std::end(r);
    return std::make_pair(std::search(first, last, std::begin(pat), std::end(pat)), last);
}

template <typename R, typename PatR, typename BinPred>
constexpr auto search(R&& r, PatR&& pat, BinPred pred)
{
    auto first = std::begin(r);
    auto last  = std::end(r);
    return std::make_pair(std::search(first, last, std::begin(pat), std::end(pat), pred), last);
}

// ---- remove / unique — return subrange {new_end, original_end} ----
template <typename R, typename T>
constexpr auto remove(R&& r, T const& val)
{
    auto first = std::begin(r);
    auto last  = std::end(r);
    return tr::subrange<decltype(first)>{std::remove(first, last, val), last};
}

template <typename R>
constexpr auto unique(R&& r)
{
    auto first = std::begin(r);
    auto last  = std::end(r);
    return tr::subrange<decltype(first)>{std::unique(first, last), last};
}

// ---- result structs for copy/transform/etc. (return {.in, .out} like ranges::) ----
template <typename I, typename O>
struct in_out_result {
    [[no_unique_address]] I in;
    [[no_unique_address]] O out;
};

template <typename I1, typename I2, typename O>
struct in_in_out_result {
    [[no_unique_address]] I1 in1;
    [[no_unique_address]] I2 in2;
    [[no_unique_address]] O out;
};

// ---- copy / transform / set_difference / unique_copy — output iter arg ----
template <typename R, typename Out>
constexpr auto copy(R&& r, Out out)
{
    auto first = std::begin(r);
    auto last  = std::end(r);
    return in_out_result<decltype(last), Out>{last, std::copy(first, last, out)};
}

template <typename R, typename Out, typename Fn>
constexpr auto transform(R&& r, Out out, Fn fn)
{
    auto first = std::begin(r);
    auto last  = std::end(r);
    return in_out_result<decltype(last), Out>{last, std::transform(first, last, out, fn)};
}

template <typename R1, typename R2, typename Out>
constexpr auto set_difference(R1&& r1, R2&& r2, Out out)
{
    auto first1 = std::begin(r1);
    auto last1  = std::end(r1);
    auto first2 = std::begin(r2);
    auto last2  = std::end(r2);
    return in_in_out_result<decltype(last1), decltype(last2), Out>{
        last1, last2,
        std::set_difference(first1, last1, first2, last2, out)};
}

template <typename R1, typename R2, typename Out, typename Comp>
constexpr auto set_difference(R1&& r1, R2&& r2, Out out, Comp comp)
{
    auto first1 = std::begin(r1);
    auto last1  = std::end(r1);
    auto first2 = std::begin(r2);
    auto last2  = std::end(r2);
    return in_in_out_result<decltype(last1), decltype(last2), Out>{
        last1, last2,
        std::set_difference(first1, last1, first2, last2, out, comp)};
}

template <typename R, typename Out>
constexpr auto unique_copy(R&& r, Out out)
{
    auto first = std::begin(r);
    auto last  = std::end(r);
    return in_out_result<decltype(last), Out>{last, std::unique_copy(first, last, out)};
}

template <typename R, typename Out, typename Pred>
constexpr auto unique_copy(R&& r, Out out, Pred pred)
{
    auto first = std::begin(r);
    auto last  = std::end(r);
    return in_out_result<decltype(last), Out>{last, std::unique_copy(first, last, out, pred)};
}

// ---- equal — two ranges ----
template <typename R1, typename R2>
constexpr bool equal(R1&& r1, R2&& r2)
{
    return std::equal(std::begin(r1), std::end(r1), std::begin(r2), std::end(r2));
}

template <typename R1, typename R2, typename Pred>
constexpr bool equal(R1&& r1, R2&& r2, Pred pred)
{
    return std::equal(std::begin(r1), std::end(r1), std::begin(r2), std::end(r2), pred);
}

#undef TR_DEFINE_RANGE_ALG_0
#undef TR_DEFINE_RANGE_ALG_1
#undef TR_DEFINE_RANGE_ALG_2
#undef TR_DEFINE_RANGE_ALG_3

// ═══════════════════════════════════════════════════════════════════════
// lexicographical_compare_three_way
// ═══════════════════════════════════════════════════════════════════════

template <typename I1, typename I2>
constexpr auto lexicographical_compare_three_way(I1 first1, I1 last1, I2 first2, I2 last2)
    -> std::strong_ordering
{
    for (; first1 != last1 && first2 != last2; ++first1, (void)++first2)
    {
        if (auto const cmp = *first1 <=> *first2; cmp != 0)
        {
            return cmp;
        }
    }
    return first1 != last1 ? std::strong_ordering::greater
         : first2 != last2 ? std::strong_ordering::less
                           : std::strong_ordering::equal;
}

// ═══════════════════════════════════════════════════════════════════════
// View replacements: keys_of, values_of, reverse_of, take_of, drop_of
// ═══════════════════════════════════════════════════════════════════════

namespace detail {

template <typename Iter, int MemberIndex>
class pair_element_iter
{
public:
    using difference_type   = typename std::iterator_traits<Iter>::difference_type;
    using iterator_category = typename std::iterator_traits<Iter>::iterator_category;
    using underlying_value_type = typename std::iterator_traits<Iter>::value_type;
    using K = std::remove_cvref_t<decltype(std::declval<underlying_value_type>().first)>;
    using V = std::remove_cvref_t<decltype(std::declval<underlying_value_type>().second)>;
    using reference   = std::conditional_t<MemberIndex == 0, K&, V&>;
    using value_type  = std::conditional_t<MemberIndex == 0, K, V>;
    using pointer     = value_type*;

    pair_element_iter() = default;
    explicit pair_element_iter(Iter it) : it_(it) {}

    reference operator*() const
    {
        if constexpr (MemberIndex == 0) return it_->first;
        else                            return it_->second;
    }
    pointer operator->() const { return &**this; }

    pair_element_iter& operator++()    { ++it_; return *this; }
    pair_element_iter  operator++(int) { auto t = *this; ++it_; return t; }
    pair_element_iter& operator--()    { --it_; return *this; }
    pair_element_iter  operator--(int) { auto t = *this; --it_; return t; }

    friend bool operator==(pair_element_iter a, pair_element_iter b) { return a.it_ == b.it_; }
    friend bool operator!=(pair_element_iter a, pair_element_iter b) { return a.it_ != b.it_; }
    friend bool operator< (pair_element_iter a, pair_element_iter b) { return a.it_ <  b.it_; }
    friend bool operator> (pair_element_iter a, pair_element_iter b) { return a.it_ >  b.it_; }
    friend bool operator<=(pair_element_iter a, pair_element_iter b) { return a.it_ <= b.it_; }
    friend bool operator>=(pair_element_iter a, pair_element_iter b) { return a.it_ >= b.it_; }

    pair_element_iter& operator+=(difference_type n) { it_ += n; return *this; }
    pair_element_iter& operator-=(difference_type n) { it_ -= n; return *this; }
    friend pair_element_iter operator+(pair_element_iter a, difference_type n) { return pair_element_iter(a.it_ + n); }
    friend pair_element_iter operator-(pair_element_iter a, difference_type n) { return pair_element_iter(a.it_ - n); }
    friend difference_type   operator-(pair_element_iter a, pair_element_iter b) { return a.it_ - b.it_; }

    reference operator[](difference_type n) const
    {
        if constexpr (MemberIndex == 0) return it_[n].first;
        else                            return it_[n].second;
    }

private:
    Iter it_;
};

} // namespace detail

// ---- keys_of / values_of ----
template <typename Container>
struct key_range
{
    Container& c;
    using iterator = detail::pair_element_iter<decltype(std::begin(c)), 0>;
    auto begin()       { return iterator{std::begin(c)}; }
    auto end()         { return iterator{std::end(c)};   }
    auto begin() const { return iterator{std::begin(c)}; }
    auto end()   const { return iterator{std::end(c)};   }
};

template <typename Container>
struct value_range
{
    Container& c;
    using iterator = detail::pair_element_iter<decltype(std::begin(c)), 1>;
    auto begin()       { return iterator{std::begin(c)}; }
    auto end()         { return iterator{std::end(c)};   }
    auto begin() const { return iterator{std::begin(c)}; }
    auto end()   const { return iterator{std::end(c)};   }
};

template <typename Container>
auto keys_of(Container& c) { return key_range<Container>{c}; }

template <typename Container>
auto values_of(Container& c) { return value_range<Container>{c}; }

// ---- reverse_of ----
template <typename R>
struct reverse_range
{
    R& r;
    using riter = std::reverse_iterator<decltype(std::begin(r))>;
    auto begin()       { return riter{std::end(r)}; }
    auto end()         { return riter{std::begin(r)}; }
    auto begin() const { return std::make_reverse_iterator(std::end(r)); }
    auto end()   const { return std::make_reverse_iterator(std::begin(r)); }
};

template <typename R>
auto reverse_of(R& r) { return reverse_range<R>{r}; }

// ---- take_of ----
template <typename R>
struct take_range
{
    R& r;
    size_t n;
    using iter = decltype(std::begin(r));
    auto begin()       { return std::begin(r); }
    auto end()         { return std::next(std::begin(r), std::min(n, (size_t)(std::end(r) - std::begin(r)))); }
    auto begin() const { return std::begin(r); }
    auto end()   const { return std::next(std::begin(r), std::min(n, (size_t)(std::end(r) - std::begin(r)))); }
};

template <typename R>
auto take_of(R& r, size_t n) { return take_range<R>{r, n}; }

// ---- drop_of ----
template <typename R>
struct drop_range
{
    R& r;
    size_t n;
    using iter = decltype(std::begin(r));
    auto begin() { return std::next(std::begin(r), std::min(n, (size_t)(std::end(r) - std::begin(r)))); }
    auto end()   { return std::end(r); }
    auto begin() const { return std::next(std::begin(r), std::min(n, (size_t)(std::end(r) - std::begin(r)))); }
    auto end()   const { return std::end(r); }
};

template <typename R>
auto drop_of(R& r, size_t n) { return drop_range<R>{r, n}; }

} // namespace tr

#endif // defined(__cplusplus) && __cplusplus >= 202002L
