// tb_util_pkg.sv — shared helpers for M1 testbenches
package tb_util_pkg;

  // 32-bit LFSR-ish PRNG so every TB is deterministic without depending on
  // simulator RNG seeding behaviour alone.
  function automatic int unsigned urand(input int unsigned seed_io, input int unsigned max_val);
    int unsigned s;
    s = seed_io * 32'd1664525 + 32'd1013904223;
    return (max_val == 0) ? 0 : (s % (max_val + 1));
  endfunction

  function automatic real ceil_ratio(input real a, input real b);
    // smallest integer n as real such that n >= a/b
    real r;
    r = a / b;
    return $rtoi($ceil(r));
  endfunction

endpackage : tb_util_pkg
