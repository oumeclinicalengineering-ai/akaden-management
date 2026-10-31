"""Offline browser integration: no external requests or Supabase resources."""
from pathlib import Path
import json
from playwright.sync_api import sync_playwright, expect

HTML = (Path(__file__).resolve().parent.parent / 'ver6-simple.html').read_text()
SDK = """
window.supabase={createClient:()=>{
 const call=async(action,args)=>{const r=await fetch('/mock',{method:'POST',body:JSON.stringify({action,args})});return r.json()};
 return {auth:{onAuthStateChange(){},getUser:async()=>({data:{user:null}}),
 signInWithPassword:async()=>({data:{user:{id:'fictional-user'}}}),signOut:async()=>({error:null})},
 from(table){const query={eq(){return query},single:()=>call('profile'),order(){return query},limit(){return query},gt(){return query},then:(resolve,reject)=>call(table).then(resolve,reject)};return {select:()=>query,insert:o=>call('insert',o),update:o=>({eq:()=>call('update',o)})}},rpc:(name,args)=>call(name,args)};
}};
"""
orders=[]
receipts=[]
rejected=[]
def route(req):
    url=req.request.url
    if url=='http://akaden.test/': return req.fulfill(body=HTML,content_type='text/html')
    if 'cdn.jsdelivr.net' in url: return req.fulfill(body=SDK,content_type='application/javascript')
    if url!='http://akaden.test/mock': return req.abort()
    body=req.request.post_data_json
    action=body['action']; args=body.get('args') or {}
    result={'data':None,'error':None}
    if action=='profile': result['data']={'display_name':'架空スタッフ','role':'staff','active':True}
    elif action=='orders': result['data']=orders
    elif action=='receipts': result['data']=receipts
    elif action=='insert': orders.append(dict(args,id='fictional-order',deleted=False))
    elif action=='add_receipt':
        total=sum(r['quantity'] for r in receipts)
        if total+args['p_quantity']>orders[0]['quantity']:
            rejected.append(args); result['error']={'message':'模擬DB：数量超過'}
        else: receipts.append({'id':str(len(receipts)+1),'order_id':args['p_order_id'],'quantity':args['p_quantity'],'receipt_date':args['p_receipt_date'],'person':args['p_person'],'memo':args['p_memo'],'created_by':'fictional-user'})
    else: raise AssertionError(action)
    req.fulfill(json=result)

with sync_playwright() as p:
    browser=p.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox'])
    contexts=[browser.new_context(viewport={'width':390,'height':844}),browser.new_context()]
    pages=[]; errors=[]
    for context in contexts:
        context.route('**/*',route)
        page=context.new_page(); page.on('pageerror',lambda e:errors.append(str(e))); pages.append(page)
        page.goto('http://akaden.test/')
        for key,value in {'url':'https://fictional.supabase.co','key':'sb_publishable_fictional','email':'demo@example.invalid','password':'fictional'}.items(): page.locator('#'+key).fill(value)
        page.locator('#signIn').click(); expect(page.locator('#app')).to_be_visible()
    a,b=pages
    a.locator('#navNew').click()
    for name,value in {'reference_no':'TEST-ONLY','item_name':'架空センサー','quantity':'5'}.items(): a.locator(f'#newOrder [name={name}]').fill(value)
    a.locator('#newOrder button').click(); expect(a.locator('#ordersRows')).to_contain_text('架空センサー')
    b.locator('#reload').click(); expect(b.locator('#ordersRows')).to_contain_text('架空センサー')
    for page in pages: page.locator('[data-open]').click()
    def receive(page,n):
        page.locator('#newReceipt [name=p_quantity]').fill(str(n)); page.locator('#newReceipt button').click()
    receive(a,3); expect(a.locator('#status')).to_have_text('受領登録しました')
    # B retains an old snapshot: server must reject over-receipt atomically.
    receive(b,3); expect(b.locator('#status')).to_contain_text('数量超過')
    receive(b,2); expect(b.locator('#status')).to_have_text('受領登録しました')
    a.locator('#navOrders').click(); a.locator('#reload').click()
    expect(a.locator('[data-label="受領済"]')).to_have_text('5')
    expect(a.locator('[data-label="残数"]')).to_have_text('0')
    assert len(rejected)==1 and sum(r['quantity'] for r in receipts)==5
    assert not errors,errors
    print('PASS: two isolated browsers, login, shared order, partial/full receipt, stale-client over-receipt rejection, no JS errors')
    browser.close()
