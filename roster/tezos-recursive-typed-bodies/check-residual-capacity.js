#!/usr/bin/env node
'use strict';
/* Genuine-CMT single-use capacity plus pending partial/omitted/overapplication
   preservation. Both layers must pass; setup failures never count as RED. */
const cp=require('node:child_process'),path=require('node:path');
for(const script of ['check-witness-inputs.js','check-native.js']){
 const result=cp.spawnSync(process.execPath,[path.join(__dirname,script)],{encoding:'utf8',timeout:120000,maxBuffer:128*1024*1024});
 if(result.stdout)process.stdout.write(result.stdout);if(result.stderr)process.stderr.write(result.stderr);
 if(result.error||result.signal||result.status===null||result.status>=2){process.exitCode=2;break;}
 if(result.status!==0){process.exitCode=result.status;break;}
}
