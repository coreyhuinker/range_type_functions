
create function to_range(low anyelement, high anyelement, bounds text, range anyrange) returns anyrange
language plpgsql immutable as $$
declare
    l_range text;
begin
    execute format('select %s($1,$2,$3)',pg_typeof(range)) using low, high, bounds into l_range;
    return l_range;
end
$$;

comment on function to_range(low anyelement, high anyelement, bounds text, range anyrange)
is E'Given a lower bound, upper bound, bounds description, return a range of the given range type.';

create function to_range(elem anyelement, range anyrange) returns anyrange
language sql immutable set search_path from current as $$
select to_range(elem,elem,'[]',range);
$$;

comment on function to_range(elem anyelement, range anyrange)
is E'Convert an element e into the range [e].';

create function element_range_comp(element anyelement, range anyrange) returns smallint
language sql strict immutable set search_path from current as $$
select  case
            when to_range(element,range) << range then -1::smallint
            when to_range(element,range) <@ range then 0::smallint
            when to_range(element,range) >> range then 1::smallint
        end;
$$;

comment on function element_range_comp(anyelement,anyrange)
is E'Perform a strcmp-like comparison of an element and a range type.\n'
    'Return 0 if the element is within the range.\n'
    'Return -1 if the element is below the lower bound of the range.\n'
    'Return 1 if the element is above the upper bound of the range.\n';

create function is_singleton(range anyrange) returns boolean
language sql immutable set search_path from current as $$
select range is not distinct from to_range(lower(range),range);
--select lower_inc(range) and upper_inc(range) and lower(range) = upper(range);
$$;

comment on function is_singleton(range anyrange)
is E'Returns true if the range has only one possible element.';


create function get_collation_expr(range anyrange) returns text
language sql stable set search_path from current as $$
select  ' COLLATE "' || l.collname::text || '"'
from    pg_range r
join    pg_collation l
on      l.oid = r.rngcollation
where   r.rngtypid = pg_typeof(range);
$$;

comment on function get_collation_expr(range anyrange)
is 'return COLLATE "foo" or null';

create function get_subtype_element_expr(range anyrange, placeholder text default 'x') returns text
language sql stable set search_path from current as $$
select  placeholder || coalesce(get_collation_expr(range),'');
$$;

comment on function get_subtype_element_expr(range anyrange, placeholder text)
is 'express a valid subtype by name with proper collation';

create function get_bound_expr(range anyrange, literal anyelement) returns text
language sql stable set search_path from current as $$
select  format('%L::%s%s',literal,format_type(rngsubtype,null), get_collation_expr(range))
from    pg_range
where   rngtypid = pg_typeof(range);
$$;

comment on function get_bound_expr(range anyrange, literal anyelement)
is E'express a value casted as the subtype of the given range';

create function get_lower_bound_condition_expr(range anyrange, placeholder text default 'x') returns text
language sql immutable set search_path from current as $$
select  case
            when lower_inf(range) then 'true'
            when isempty(range) then 'false'
            when lower_inc(range) then format('%s >= %s',
                                                get_subtype_element_expr(range,placeholder),
                                                get_bound_expr(range,lower(range)))
            else format('%s > %s',
                        get_subtype_element_expr(range,placeholder),
                        get_bound_expr(range,lower(range)))
        end;
$$;

comment on function get_lower_bound_condition_expr(anyrange,text)
is E'Given a range and a placeholder value, construct the where-clause fragment for the lower bound of the range\n';

create function get_upper_bound_condition_expr(range anyrange, placeholder text default 'x') returns text
language sql immutable set search_path from current as $$
select  case
            when upper_inf(range) then 'true'
            when isempty(range) then 'false'
            when upper_inc(range) then format('%s <= %s',
                                                get_subtype_element_expr(range,placeholder),
                                                get_bound_expr(range,upper(range)))
            else format('%s < %s',
                        get_subtype_element_expr(range,placeholder),
                        get_bound_expr(range,upper(range)))
        end;
$$;

comment on function get_upper_bound_condition_expr(anyrange,text)
is E'Given a range and a placeholder value, construct the where-clause fragment for the upper bound of the range';

create function get_bounds_condition_expr(range anyrange, placeholder text default 'x') returns text
language sql immutable set search_path from current as $$
select  case
            when lower(range) = upper(range) then format('%s = %L',placeholder,lower(range))
            when isempty(range) then 'false'
            when lower_inf(range) and upper_inf(range) then 'true'
            when lower_inf(range) then get_upper_bound_condition_expr(range,placeholder)
            when upper_inf(range) then get_lower_bound_condition_expr(range,placeholder)
            else format('%s and %s',
                        get_lower_bound_condition_expr(range,placeholder),
                        get_upper_bound_condition_expr(range,placeholder))
        end;
$$;

comment on function get_bounds_condition_expr(anyrange,text)
is E'Given a range and a placeholder value, construct the where-clause fragment for the range';


-- grant execute on all functions in this extension to public
do $$
declare r record;
begin
    for r in (  select	p.proname, pg_get_function_identity_arguments(p.oid) as args
                from	pg_proc p
                join	pg_depend d on d.objid = p.oid and d.deptype = 'e'
                join	pg_extension x on x.oid = d.refobjid
                where   x.extname = 'range_type_functions' )
    loop
        execute format('grant execute on function %s(%s) to public',r.proname,r.args);
    end loop;
end
$$;


