#!/usr/bin/env node
'use strict';
/* The full genuine-CMT capacity controls live in check-witness-inputs.js.
   Keep this entry point explicit for CHECK-6 and preserve its exit taxonomy. */
const cp=require('node:child_process'),path=require('node:path');
const result=cp.spawnSync(process.execPath,[path.join(__dirname,'check-witness-inputs.js')],{encoding:'utf8'});
if(result.stdout)process.stdout.write(result.stdout);if(result.stderr)process.stderr.write(result.stderr);
if(result.error||result.signal||result.status===null||result.status>=2){process.exitCode=2;}
else process.exitCode=result.status;
