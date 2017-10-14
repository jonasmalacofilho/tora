/*
	Tora - Neko Application Server
	Copyright (C) 2008-2016 Haxe Foundation

	This library is free software; you can redistribute it and/or
	modify it under the terms of the GNU Lesser General Public
	License as published by the Free Software Foundation; either
	version 2.1 of the License, or (at your option) any later version.

	This library is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
	Lesser General Public License for more details.

	You should have received a copy of the GNU Lesser General Public
	License along with this library; if not, write to the Free Software
	Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
*/
package fcgi;

import fcgi.Message;
import fcgi.StatusCode;
import fcgi.MultipartState;

import haxe.ds.StringMap;
import haxe.io.Bytes;

import tora.Code;

class ClientFcgi extends Client
{
	inline static var NL = '\r\n';
	
	//fast-cgi
	var requestId : Int;
	var role : Role;
	var flags : Int;
	
	var fcgiParams : List<{ k : String, v : String }>;
	
	var contentType : String;
	var contentLength : Int;
	
	var doMultipart : Bool;
	var mpstate : MultipartState;
	var mpbuffer : String;
	var mpbufpos : Int;
	var mpboundary : Null<String>;
	var mpeof : Bool;
	var mpbufsize : Int;

	var dataIn : String;
	
	var statusOut : String;
	var headersOut : List<String>;
	var stdOut : String;
	
	var statusSent : Bool;
	var bodyStarted : Bool;
	
	var multiparts : List<{name : String, file : String, data : String}>;
	var fileMessages : List<{ code : Code, str : String }>;
	
	public function new(s,secure)
	{
		super(s, secure);
		
		requestId = null;
		role = null;
		flags = null;
		
		fcgiParams = new List();
		
		contentType = null;
		contentLength = null;
		
		doMultipart = false;
		mpstate = null;
		mpbuffer = null;
		mpbufpos = -1;
		mpboundary = null;
		mpeof = false;
		mpbufsize = 0;

		dataIn = null;
		
		statusOut = null;
		headersOut = null;
		stdOut = null;
		
		statusSent = false;
		bodyStarted = false;
		
		multiparts = new List();
		fileMessages = new List();
	}
	
	override public function prepare( ) : Void
	{
		super.prepare();
		
		requestId = null;
		role = null;
		flags = null;
		
		fcgiParams = new List();
		
		mpboundary = null;

		contentType = null;
		contentLength = null;
		
		doMultipart = false;
		mpstate = null;
		mpbuffer = null;
		mpbufpos = -1;
		mpboundary = null;
		mpeof = false;
		mpbufsize = 0;

		dataIn = null;
		
		statusOut = null;
		headersOut = null;
		stdOut = null;
		
		statusSent = false;
		bodyStarted = false;
		
		multiparts = new List();
		fileMessages = new List();
	}
	
	override public function sendMessageSub( code : Code, msg : String, pos : Int, len : Int ) : Void
	{
		switch(code)
		{
			case CPrint:
				if ( stdOut == null ) stdOut = ''; stdOut += msg.substr(pos, len);
			
			default: Tora.log(Std.string(['sendMessageSub', code, msg, pos, len]));
		}
	}
	
	override public function sendMessage( code : Code, msg : String ) : Void
	{
		switch(code)
		{
			case CReturnCode: statusOut = msg;
			
			case CHeaderKey: key = msg;
			case CHeaderValue, CHeaderAddValue:
				if ( headersOut == null ) headersOut = new List<String>();
				headersOut.add(key + ':' + msg);
			
			case CPrint: if ( stdOut == null ) stdOut = ''; stdOut += msg;
			
			case CFlush: var s = makeStatus() + makeHeaders() + makeBody();
				
				if( s.length > 0 )
					MessageHelper.write(sock.output, requestId, STDOUT(s), true);
			
			case CExecute: var s = makeStatus() + makeHeaders() + makeBody('');
				
				MessageHelper.write(sock.output, requestId, STDOUT(s));
				MessageHelper.write(sock.output, requestId, END_REQUEST(202, REQUEST_COMPLETE));
			
			case CError: var s = makeStatus("500") + NL + msg;
				if ( stdOut != null ) s += NL + stdOut;
				
				Tora.log(msg);
				Tora.log(s);
				
				MessageHelper.write(sock.output, requestId, STDOUT(s));
				MessageHelper.write(sock.output, requestId, STDERR(msg));
				MessageHelper.write(sock.output, requestId, END_REQUEST(202, REQUEST_COMPLETE));
				throw msg;
			
			case CRedirect:
				if ( headersOut == null ) headersOut = new List<String>(); headersOut.add('Location:' + msg);
				
				var s = makeStatus("302") + makeHeaders() + NL;
				
				MessageHelper.write(sock.output, requestId, STDOUT(s));
				MessageHelper.write(sock.output, requestId, END_REQUEST(202, REQUEST_COMPLETE));
			
			case CQueryMultipart:
				doMultipart = true;
				mpbufsize = Std.parseInt(msg);
			case CLog:
				// save 2 file
				//Tora.log('App log: ' + msg);
			
			//case CListen:
/*
			CUri
			CTestConnect
			CPostData
			
			CPartKey
			CPartFilename
			CPartDone
			CPartData
			
			CParamValue
			CParamKey
			
			CHttpMethod
			CHostResolve
			CHostName
			CGetParams
			CFile
			CClientIP
*/
			default: Tora.log(Std.string(['sendMessage', code, msg]));
		}
	}
	inline function makeStatus( ?status : String ) : String
	{
		if ( status != null )
			statusOut = status;
		
		if ( statusOut == null )
			statusOut = "200";
		
		var s : String = '';
		if ( !statusSent )
		{
			s += 'Status: ' + statusOut + ' ' + (statusOut.length == 3 ? StatusCode.CODES.get(statusOut) : '') + NL;
			statusSent = true;
		}
		return s;
	}
	inline function makeHeaders( ) : String
	{
		var s = '';
		if ( headersOut != null )
			s = headersOut.join(NL) + NL;
		headersOut = null;
		return s;
	}
	inline function makeBody( ?b : String ) : String
	{
		if ( b != null && stdOut == null )
			stdOut = b;
		
		var s = '';
		if ( stdOut != null )
		{
			if ( !bodyStarted )
			{
				s += NL;
				bodyStarted = true;
			}
			
			s += stdOut;
			stdOut = null;
		}
		return s;
	}
	
	override public function readMessageBuffer( buf : Bytes ) : Code
	{
		while (doMultipart && !processMultipart()) {
			while (!mpeof && !processMessage()) {
			}
		}

		if ( fileMessages.length > 0 )
		{
			var m = fileMessages.pop();
			
			if ( m.str != null )
			{
				bytes = m.str.length;
				buf.blit(0, Bytes.ofString(m.str), 0, m.str.length);
			}
			
			return m.code;
		}
		
		return super.readMessageBuffer(buf);
	}


	inline function startsWith(buf:String, start:String, ?bufPos=0)
	{
		return buf.length >= bufPos + start.length && buf.substr(bufPos, start.length) == start;
	}


	function processMultipart():Bool
	{
		var FETCH = false;
		var CONTROL = true;

		while (true) {
			switch mpstate {
			case MFinished:
				mpbuffer = null;
				mpbufpos = -1;
				fileMessages.add({ code:CExecute, str:null });
				doMultipart = false;
				return CONTROL;
			case MBeforeFirstPart:
				var b = mpbuffer.indexOf(mpboundary, mpbufpos);
				if (b >= 0) {
					mpbufpos = b + mpboundary.length;  // jump over boundary but not -- or \r\n
					mpstate = MPartInit;
					continue;
				}
				return FETCH;
			case MPartInit:
				if (mpbuffer.substr(mpbufpos, 2) == "--") {
					mpbufpos += 2; // mark -- as read
					mpstate = MFinished;
				} else {
					mpbufpos += 2;  // jump over \r\n
					mpstate = MPartReadingHeaders;
				}
			case MPartReadingHeaders:
				var b = mpbuffer.indexOf("\r\n\r\n", mpbufpos);
				if (b >= 0) {
					while (mpbufpos < b && !startsWith(mpbuffer, "Content-Disposition:", mpbufpos)) {
						mpbufpos = mpbuffer.indexOf("\r\n", mpbufpos) + 2;  // jump over \r\n
					}
					if (!startsWith(mpbuffer, "Content-Disposition:", mpbufpos)) {
						throw "Assert failed: part missing Content-Disposition header";
					}
					var fn = mpbuffer.indexOf('filename=', mpbufpos);
					if (fn > 0 && fn < b) {
						fn += 9;
						var q = mpbuffer.charAt(fn++);
						var filename = mpbuffer.substring(fn, mpbuffer.indexOf(q, fn));
						fileMessages.add({ code:CPartFilename, str:filename });
					}
					var n = mpbuffer.indexOf('name=', mpbufpos);
					if (n > 0 && n < b) {
						n += 5;
						var q = mpbuffer.charAt(n++);
						var name = mpbuffer.substring(n, mpbuffer.indexOf(q, n));
						fileMessages.add({ code:CPartKey, str:name });
					}
					mpbufpos = b + 4;  // jump over \r\n\r\n
					mpstate = MPartReadingData;
					return CONTROL;
				}
				return FETCH;
			case MPartReadingData:
				var b = mpbuffer.indexOf(mpboundary, mpbufpos);
				if (b >= 0) {
					while (mpbufpos < b - 2) {  // remove trailling \r\n
						var len = b - 2 - mpbufpos;
						if (len > mpbufsize)
							len = mpbufsize;
						fileMessages.add({ code:CPartData, str:mpbuffer.substr(mpbufpos, len) });
						mpbufpos += len;
					}
					fileMessages.add({ code:CPartDone, str:null });
					mpbufpos = b + mpboundary.length;  // jump over boundary but not \r\n
					mpstate = MPartInit;
					return CONTROL;
				} else {
					b = mpbuffer.indexOf("\r\n--", mpbufpos);
					if (mpbufpos >= mpbuffer.length)
						break;
					if (b < 0 || !startsWith(mpboundary, mpbuffer.substr(mpbufpos + 2, mpboundary.length))) {
						while (mpbufpos < mpbuffer.length) {
							var len = mpbuffer.length - mpbufpos;
							if (len > mpbufsize)
								len = mpbufsize;
							fileMessages.add({ code:CPartData, str:mpbuffer.substr(mpbufpos, len) });
							mpbufpos += len;
						}
						return CONTROL;
					}
				}
			}
		}
		if (mpbufpos > 0) {
			mpbuffer = mpbuffer.substr(mpbufpos);
			mpbufpos = 0;
		}
		return FETCH;
	}

	override public function processMessage( ) : Bool
	{
		var m = MessageHelper.read(sock.input);
		
		if ( requestId == null )
			requestId = m.requestId;
		else if ( requestId != m.requestId )
			throw "Wrong requestID. Expect: " + requestId +". Get: " + m.requestId;
		
		switch( m.message )
		{
			case BEGIN_REQUEST(role, flags):
				this.role = role;
				this.flags = flags;
			
			case ABORT_REQUEST(_):
			//case ABORT_REQUEST(app, protocol):
				// The Web server sends a FCGI_ABORT_REQUEST record to abort a request.
				// After receiving {FCGI_ABORT_REQUEST, R}, the application responds as soon as possible with {FCGI_END_REQUEST, R, {FCGI_REQUEST_COMPLETE, appStatus}}.
				// This is truly a response from the application, not a low-level acknowledgement from the FastCGI library.
				MessageHelper.write(sock.output, requestId, END_REQUEST(202, REQUEST_COMPLETE));
				this.execute = false;

			case STDIN(s) if (mpboundary != null):
				if (s == "")
					mpeof = true;
				mpbuffer += s;
				execute = true;
				return true;

			case STDIN(s) if (s == ""):
				for (p in getParamValues(getParams, true))
					params.push(p);
				for (p in getParamValues(postData, false))
					params.push(p);
				if (postData == null)
					postData = "";
				this.execute = true;
				return true;

			case STDIN(s) if ((postData != null ? postData.length : 0) + s.length > (1 << 20)):
				// hardcoded limit: 1 MiB
				// (256 KiB, as specified in neko.Web.getPostData() docs, is too little; plus, 1 MiB is Nginx's default)
				Tora.log("Maximum POST data exceeded (1 MiB). Try using multipart encoding");
				MessageHelper.write(sock.output, requestId, END_REQUEST(413, REQUEST_COMPLETE));
				this.execute = false;
				return true;

			case STDIN(s):
				if (postData == null)
					postData = '';
/*CPostData*/	postData += s;

			case DATA(s): // not implimented @ nginx
				// FCGI_DATA is a second stream record type used to send additional data to the application.
				if ( s == "" )
				{
					return false;
				}
				if ( dataIn == null ) dataIn = '';
				dataIn += s;
				
			
			case PARAMS(h): for ( name in h.keys() ) { var value = h.get(name); switch( name )
			{
/*CFile*/		case 'SCRIPT_FILENAME': if ( secure ) file = value;		// need add doc root
/*CUri*/		case 'DOCUMENT_URI': uri = value;						//DOCUMENT_URI + QUERY_STRING = REQUEST_URI
/*CClientIP*/	case 'REMOTE_ADDR': if ( secure ) ip = value;			//
/*CGetParams*/	case 'QUERY_STRING': getParams = value;
/*CHostName*/	case 'SERVER_NAME': if ( secure ) hostName = value; 	//SERVER_NAME + SERVER_PORT = HTTP_HOST
/*CHttpMethod*/	case 'REQUEST_METHOD': httpMethod = value;

/*CHeaderKey*/	
/*CHeaderValue*/
/*CHeaderAddValue*/
				default: var header = false, n = '';
				
					if ( name.substr(0, 5) == "HTTP_" )
					{
						header = true;
						n = name.substr(5);
					}
					else if ( name == 'CONTENT_TYPE' )
					{
						header = true;
						n = name;
						if ( value == null || value.length < 1 ) continue;
						
						contentType = value;

						if (contentType.indexOf('multipart/form-data') > -1) {
							var pos = contentType.indexOf('boundary=');
							if (pos < 0)
								return false;
							pos += 9;  //boundary=
							mpboundary = '--' + contentType.substr(pos);
							mpstate = MBeforeFirstPart;
							mpbuffer = "";
							mpbufpos = 0;
							doMultipart = false;
						}
					}
					else if ( name == 'CONTENT_LENGTH' ) 
					{
						header = true;
						n = name;
						if ( value == null || value.length < 1 ) continue;
						
						contentLength = Std.parseInt(value);
					}
					
					if ( header )
					{
						var key = '';
						var ps = n.toLowerCase().split("_");
						var first = true;
						for ( p in ps )
						{
							if ( first ) first = false; else key += '-';
							
							key += p.charAt(0).toUpperCase() + p.substr(1);
						}
						headers.push( { k:key, v:value } );
					}
					else
						fcgiParams.push({ k:name, v:value });
			}}
			
			case GET_VALUES(_): // The Web server can query specific variables within the application.
			//case GET_VALUES(h):
				
			
			default: throw "Unexpected " + Std.string(m.message);
		}
		
		return false;
	}
	
	static function getParamValues( data : String, ?isGet : Bool = false ) : List<{ k : String, v : String }>
	{
		var out = new List();
		if ( data == null || data.length == 0 )
			return out;
		
		if ( isGet )
			data = StringTools.replace(data, ";", "&");
		
		for ( part in data.split("&") )
		{
			var i = part.indexOf("=");
/*CParamKey*/			
			var k = part.substr(0, i);
/*CParamValue*/
			var v = part.substr(i + 1);
			if ( v != "" )
				v = StringTools.urlDecode(v);
			
			out.push({k:k, v:v});
		}
		return out;
	}
}
