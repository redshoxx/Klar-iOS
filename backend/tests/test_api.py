import uuid
from datetime import datetime, timezone

def signup(client, email='test@example.com'):
    response = client.post('/v1/auth/register', json={'email':email, 'password':'VerySecurePassword123!'} )
    assert response.status_code == 201, response.text
    return response.json()

def headers(value): return {'Authorization': 'Bearer ' + value['access_token']}

def task(title='Einkaufen'):
    return {'title':title,'completed':False,'priority':'mittel','project':'Haushalt','notes':'','repeat':'nie','due_at':None}

def test_register_login_refresh_logout(client):
    creds = signup(client)
    assert client.get('/v1/me',headers=headers(creds)).json()['email']=='test@example.com'
    r = client.post('/v1/auth/refresh',json={'refresh_token':creds['refresh_token']})
    assert r.status_code == 200
    new = r.json()
    assert client.post('/v1/auth/refresh',json={'refresh_token':creds['refresh_token']}).status_code == 401
    assert client.post('/v1/auth/logout',json={'refresh_token':new['refresh_token']}).status_code == 204
    assert client.post('/v1/auth/refresh',json={'refresh_token':new['refresh_token']}).status_code == 401
    assert client.post('/v1/auth/login', json={'email':'test@example.com','password':'VerySecurePassword123!'}).status_code == 200

def test_sync_create_update_delete_and_conflict(client):
    auth=signup(client)
    id=str(uuid.uuid4()); h=headers(auth)
    def push(base,deleted=False,t='Rechnung prüfen'):
        return client.post('/v1/sync/push', headers=h,json={'mutations':[{'kind':'tasks','id':id,'base_version':base,'deleted':deleted,'data':task(t) if not deleted else {}}]})
    a=push(0); assert a.status_code==200, a.text
    assert a.json()['applied'][0]['version']==1
    assert push(0).status_code==409
    assert push(1,t='Rechnung bezahlen').json()['applied'][0]['version']==2
    pull=client.get('/v1/sync/pull?after=0',headers=h).json()
    assert [x['version'] for x in pull['changes']]==[1,2]
    assert pull['changes'][1]['data']['title']=='Rechnung bezahlen'
    assert push(2,deleted=True).status_code==200
    assert client.get('/v1/sync/pull?after='+str(pull['next_cursor']),headers=h).json()['changes'][0]['deleted']

def test_users_strictly_isolated(client):
    a=signup(client,'a@example.com'); b=signup(client,'b@example.com')
    entry=str(uuid.uuid4())
    first=client.post('/v1/sync/push',headers=headers(a),json={'mutations':[{'kind':'tasks','id':entry,'base_version':0,'data':task()}]})
    assert first.status_code==200
    assert client.get('/v1/sync/pull',headers=headers(b)).json()['changes']==[]
    assert client.post('/v1/sync/push',headers=headers(b),json={'mutations':[{'kind':'tasks','id':entry,'base_version':0,'data':task('Andere Aufgabe')}]}).status_code==200
    assert client.get('/v1/sync/pull',headers=headers(a)).json()['changes'][0]['data']['title']=='Einkaufen'

def test_validation_and_atomicity(client):
    a=signup(client); h=headers(a)
    doc={'kind':'transactions','id':str(uuid.uuid4()),'base_version':0,'data':{'title':'Milch','amount_cents':-139,'category':'Lebensmittel','booked_at':'2026-11-12T15:00:00Z'}}
    bad={'kind':'transactions','id':str(uuid.uuid4()),'base_version':0,'data':{'title':'','amount_cents':999999999999,'category':'Lebensmittel','booked_at':'2026-11-12T15:00:00Z'}}
    assert client.post('/v1/sync/push',headers=h,json={'mutations':[doc,bad]}).status_code==422
    assert client.get('/v1/sync/pull',headers=h).json()['changes']==[]
    assert client.post('/v1/sync/push',headers=h,json={'mutations':[doc]}).status_code==200

def test_delete_account_cleans_records(client):
    a=signup(client)
    h=headers(a)
    assert client.delete('/v1/account',headers=h).status_code==204
    assert client.get('/v1/me',headers=h).status_code==401

def test_rate_limit_and_auth(client):
    assert client.get('/v1/sync/pull').status_code==401
    signup(client)
    for i in range(5):
        r=client.post('/v1/auth/login',json={'email':'test@example.com','password':'IncorrectPassword123!'})
        assert r.status_code==401
    assert client.post('/v1/auth/login',json={'email':'test@example.com','password':'IncorrectPassword123!'}).status_code==429

def test_registration_persists_parent_before_session_tokens(client):
    """Regression: PostgreSQL rejects token rows referring to an unflushed user."""
    email = 'foreign-key-regression@example.com'
    credentials = signup(client, email)
    assert client.get('/v1/me', headers=headers(credentials)).json()['email'] == email
    assert client.post('/v1/auth/login', json={
        'email': email, 'password': 'VerySecurePassword123!'
    }).status_code == 200
    assert client.post('/v1/auth/register', json={
        'email': email, 'password': 'VerySecurePassword123!'
    }).status_code == 409
