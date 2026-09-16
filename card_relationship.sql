Replace `<CARD_CUSTOMER_NUMBER>` with the V10 customer number.

```sql
with customer as (
  select
    customer_id,
    card_customer_key,
    card_customer_business_key
  from SAS_MIGRATION_WORKSPACE.CORE.CARD_CUSTOMER
  where customer_id = '<CARD_CUSTOMER_NUMBER>'
    and is_current_flag = 'Y'
    and coalesce(is_deleted_flag, 'N') <> 'Y'
),

accounts as (
  select
    a.agreement_id as card_account_number,
    a.card_account_key,
    a.card_account_business_key,
    a.card_customer_key as account_customer_key
  from SAS_MIGRATION_WORKSPACE.CORE.CARD_ACCOUNT a
  inner join customer c
    on a.card_customer_key = c.card_customer_key
  where a.is_current_flag = 'Y'
    and coalesce(a.is_deleted_flag, 'N') <> 'Y'
),

payment_instruments as (
  select
    p.payment_instrument_id,
    p.payment_instrument_key,
    p.primary_account_number,
    p.card_account_key,
    p.card_customer_key as instrument_customer_key,
    p.payment_instrument_type_key,
    p.card_status_key,
    p.valid_from_datetime,
    p.valid_to_datetime,
    p.is_current_flag
  from SAS_MIGRATION_WORKSPACE.CORE.CARD_PAYMENT_INSTRUMENT p
  where p.is_current_flag = 'Y'
    and coalesce(p.is_deleted_flag, 'N') <> 'Y'
)

select
  c.customer_id as card_customer_number,
  c.card_customer_key,
  a.card_account_number,
  a.card_account_key,
  p.payment_instrument_id,
  p.primary_account_number,
  p.payment_instrument_key,
  p.payment_instrument_type_key,
  p.card_status_key,
  case
    when p.instrument_customer_key = c.card_customer_key
      then 'MATCHES_ACCOUNT_CUSTOMER'
    when p.instrument_customer_key is null
      then 'PAYMENT_INSTRUMENT_CUSTOMER_MISSING'
    else 'DIFFERENT_PAYMENT_INSTRUMENT_CUSTOMER'
  end as customer_relationship_status
from customer c
left join accounts a
  on 1 = 1
left join payment_instruments p
  on p.card_account_key = a.card_account_key
order by a.card_account_number, p.payment_instrument_id;
```

To see the cardinality summary:

```sql
select
  c.customer_id as card_customer_number,
  count(distinct a.card_account_key) as current_card_accounts,
  count(distinct p.payment_instrument_key) as current_payment_instruments
from SAS_MIGRATION_WORKSPACE.CORE.CARD_CUSTOMER c
left join SAS_MIGRATION_WORKSPACE.CORE.CARD_ACCOUNT a
  on a.card_customer_key = c.card_customer_key
 and a.is_current_flag = 'Y'
 and coalesce(a.is_deleted_flag, 'N') <> 'Y'
left join SAS_MIGRATION_WORKSPACE.CORE.CARD_PAYMENT_INSTRUMENT p
  on p.card_account_key = a.card_account_key
 and p.is_current_flag = 'Y'
 and coalesce(p.is_deleted_flag, 'N') <> 'Y'
where c.customer_id = '<CARD_CUSTOMER_NUMBER>'
  and c.is_current_flag = 'Y'
  and coalesce(c.is_deleted_flag, 'N') <> 'Y'
group by c.customer_id;
```


-- sql to list customer id and count current card account and count current payment instrutment
select
  c.customer_id,
  count(distinct a.card_account_key) as current_card_account_count,
  count(distinct p.card_payment_instrument_key) as current_payment_instrument_count
from SAS_MIGRATION_WORKSPACE.CORE.CARD_CUSTOMER c
left join SAS_MIGRATION_WORKSPACE.CORE.CARD_ACCOUNT a
  on a.card_customer_key = c.card_customer_key
 and a.is_current_flag = 'Y'
 and coalesce(a.is_deleted_flag, 'N') <> 'Y'
left join SAS_MIGRATION_WORKSPACE.CORE.CARD_PAYMENT_INSTRUMENT p
  on p.card_account_key = a.card_account_key
 and p.is_current_flag = 'Y'
 and coalesce(p.is_deleted_flag, 'N') <> 'Y'
where c.is_current_flag = 'Y'
  and coalesce(c.is_deleted_flag, 'N') <> 'Y'
group by c.customer_id
order by current_payment_instrument_count desc, current_card_account_count desc, c.customer_id;