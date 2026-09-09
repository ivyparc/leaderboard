import test from 'node:test';
import assert from 'node:assert/strict';
import { createLeaderboardClient } from '../src/leaderboardClient.js';

test('client uses reserved names and persistent server period for writes and reads', async () => {
 const calls=[];
 const values=new Map();
 const client=createLeaderboardClient({namespace:'test',supabaseUrl:'https://example.test',supabaseAnonKey:'test',storage:{getItem:k=>values.get(k),setItem:(k,v)=>values.set(k,v)},fetchImpl:async(url,options)=>{
  const path=String(url);calls.push({path,options});
  if(path.endsWith('/leaderboard_period')) return new Response(JSON.stringify('2020-01'));
  if(path.endsWith('/leaderboard_name')) return new Response(JSON.stringify('AzureBison53'));
  return new Response(JSON.stringify([]));
 }});
 assert.equal(await client.getOrCreatePlayerName(),'AzureBison53');
 await client.submitScore(50);
 const write=calls.find(c=>c.options.method==='POST'&&c.path.includes('on_conflict'));
 assert.equal(JSON.parse(write.options.body).period,'2020-01');
 assert.equal(JSON.parse(write.options.body).name,'AzureBison53');
 await client.fetchSnapshot();
 assert.ok(calls.some(c=>new URL(c.path).searchParams.get('period')==='eq.2020-01'));
});

test('legacy endpoint must explicitly implement reservation instead of fake success', async()=>{
 const client=createLeaderboardClient({namespace:'test',endpoint:'https://example.test',storage:{getItem:()=> 'saved-id',setItem:()=>{}},fetchImpl:async()=>new Response('{}')});
 await assert.rejects(client.getOrCreatePlayerName(),/must implement/);
});
