"""Concurrent PostgreSQL integration test. Disposable synthetic database only.
Run after fixture, draft guard, assertions, and receipts fixture, using psql.
Optional argument is a local disposable Docker container name.
"""
import subprocess
import sys
import time

command = ['psql'] if len(sys.argv)==1 else ['docker','--host=unix:///var/run/docker.sock','exec','-i',sys.argv[1],'psql','-U','postgres','-d','isolated_ver6']
command += ['-X','-v','ON_ERROR_STOP=1','-At']
ORDER="'11111111-1111-4111-8111-111111111111'"
RECEIPT="'22222222-2222-4222-8222-222222222222'"
OTHER="'44444444-4444-4444-8444-444444444444'"
def sql(text,ok=True):
    result=subprocess.run(command+['-c',text],capture_output=True,text=True,timeout=15)
    assert (result.returncode==0)==ok,(text,result.stdout,result.stderr)
    return result.stdout.strip()
def reset():
    sql(f'TRUNCATE receipts,audit_events; UPDATE orders SET quantity=5; INSERT INTO receipts VALUES({RECEIPT},{ORDER},3); TRUNCATE audit_events;')
def race(first,second,first_ok=True,second_ok=True):
    # Hold the shared order lock; wait until the first connection is sleeping
    # with it held before starting the competing connection.
    leader=subprocess.Popen(command+['-c',f"SET application_name='ver6_race_leader'; BEGIN; SELECT 1 FROM orders WHERE id={ORDER} FOR UPDATE; SELECT pg_sleep(1); {first}; COMMIT;"],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    try:
        deadline=time.monotonic()+8
        while sql("SELECT count(*) FROM pg_stat_activity WHERE application_name='ver6_race_leader' AND wait_event='PgSleep'")!='1':
            assert time.monotonic()<deadline,'leader failed to reach lock barrier'
            time.sleep(.02)
        sql(second,ok=second_ok)
        out,err=leader.communicate(timeout=15)
        assert (leader.returncode==0)==first_ok,(out,err)
    finally:
        if leader.poll() is None: leader.kill();leader.communicate()
    assert sql('SELECT (SELECT sum(quantity) FROM receipts)<=quantity FROM orders')=='t'

reset()
sql('UPDATE orders SET quantity=2',ok=False)
assert sql('SELECT quantity FROM orders')=='5'
sql('UPDATE orders SET quantity=3')
assert sql('SELECT quantity FROM orders')=='3'
print('PASS: quantity 2 rejected; quantity 3 accepted for received total 3')

reset()
race(f'SELECT test_receipt_change({RECEIPT},2)',f'SELECT test_receipt_change({OTHER},2)',second_ok=False)
assert sql('SELECT sum(quantity) FROM receipts')=='5'
assert sql("SELECT count(*) FROM audit_events WHERE object_name='receipts'")=='1'
print('PASS: two concurrent receipts cannot exceed order; rejected write has no audit entry')

reset()
race(f'SELECT test_receipt_change({RECEIPT},2)','UPDATE orders SET quantity=3',second_ok=False)
assert sql('SELECT quantity FROM orders')=='5'
reset()
race('UPDATE orders SET quantity=3',f'SELECT test_receipt_change({OTHER},2)',second_ok=False)
assert sql('SELECT sum(quantity) FROM receipts')=='3'
print('PASS: receipt versus order reduction, both lock orderings')

reset()
sql(f'SELECT test_receipt_change({RECEIPT},1)')
assert sql('SELECT sum(quantity) FROM receipts')=='4'
sql(f'SELECT test_receipt_change({RECEIPT},2)',ok=False)
sql(f'SELECT test_receipt_cancel({RECEIPT})')
assert sql('SELECT count(*) FROM receipts')=='0'
assert sql("SELECT string_agg(action_name,',' ORDER BY id) FROM audit_events WHERE object_name='receipts'")=='UPDATE,DELETE'
print('PASS: receipt correction/cancellation totals and audit; rejected correction rolls back')
