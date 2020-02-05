module.exports =
/******/ (function(modules, runtime) { // webpackBootstrap
/******/ 	"use strict";
/******/ 	// The module cache
/******/ 	var installedModules = {};
/******/
/******/ 	// The require function
/******/ 	function __webpack_require__(moduleId) {
/******/
/******/ 		// Check if module is in cache
/******/ 		if(installedModules[moduleId]) {
/******/ 			return installedModules[moduleId].exports;
/******/ 		}
/******/ 		// Create a new module (and put it into the cache)
/******/ 		var module = installedModules[moduleId] = {
/******/ 			i: moduleId,
/******/ 			l: false,
/******/ 			exports: {}
/******/ 		};
/******/
/******/ 		// Execute the module function
/******/ 		modules[moduleId].call(module.exports, module, module.exports, __webpack_require__);
/******/
/******/ 		// Flag the module as loaded
/******/ 		module.l = true;
/******/
/******/ 		// Return the exports of the module
/******/ 		return module.exports;
/******/ 	}
/******/
/******/
/******/ 	__webpack_require__.ab = __dirname + "/";
/******/
/******/ 	// the startup function
/******/ 	function startup() {
/******/ 		// Load entry module and return exports
/******/ 		return __webpack_require__(874);
/******/ 	};
/******/
/******/ 	// run startup
/******/ 	return startup();
/******/ })
/************************************************************************/
/******/ ({

/***/ 382:
/***/ (function() {

eval("require")("@actions/core");


/***/ }),

/***/ 706:
/***/ (function() {

eval("require")("@actions/exec");


/***/ }),

/***/ 874:
/***/ (function(__unusedmodule, __unusedexports, __webpack_require__) {

const core = __webpack_require__(382);
const exec = __webpack_require__(706);

async function run() {
    try {
        const folder = __dirname.replace(/[/\\]dist$/, '')
        const script = `${folder}/action.ps1`
        await exec.exec('pwsh', ['-f', script])
    } catch (error) {
        core.setFailed(error.message)
    }
}
run()


/***/ })

/******/ });