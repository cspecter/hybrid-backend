-- "x" is not a stopword. It marks a cross, and a cross is its own product:
-- Purple Punch x SOAP is not Purple Punch. Removing it would have let the subset
-- merge collapse the two.
update public.product_terms
   set pattern = '\m(and|or|of|the|with|for|in|on|at|by|to|an|a)\M'
 where kind = 'noise' and pattern = '\m(and|or|of|the|with|for|in|on|at|by|to|an|a|x)\M';
