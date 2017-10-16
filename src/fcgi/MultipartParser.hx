package fcgi;

import haxe.io.Bytes;
import neko.NativeString;

enum MultipartState {
	MBeforeFirstPart;
	MPartInit;
	MPartReadingHeaders;
	MPartReadingData;
	MFinished;
}

typedef MultipartMessage = {
	code:tora.Code,
	buffer:Null<String>,
	start:Int,
	length:Int,
	?next:Null<MultipartMessage>
}

class MultipartParser {
	public var boundary(default,null):String;
	public var outputSize:Int;

	var state = MBeforeFirstPart;
	var buf = "";
	var pos = 0;
	var queue:MultipartMessage;

	public function new(boundary)
	{
		this.boundary = boundary;
	}

	public function feed(s:String)
	{
		var curlen = buf.length - pos;
		var b = Bytes.alloc(curlen + s.length);
		b.blit(0, Bytes.ofData(NativeString.ofString(buf)), pos, curlen);
		b.blit(curlen, Bytes.ofData(NativeString.ofString(s)), 0, s.length);
		buf = NativeString.toString(b.getData());
		pos = 0;
	}

	public function read()
	{
		if (queue != null)
			return pop();
		while (true) {
			switch state {
			case MBeforeFirstPart:
				var b = buf.indexOf(boundary, pos);
				if (b >= 0) {
					pos = b + boundary.length;  // jump over boundary but not -- or \r\n
					state = MPartInit;
					continue;
				}
				return null;
			case MPartInit:
				if (buf.substr(pos, 2) == "--") {
					pos += 2; // mark -- as read
					state = MFinished;
				} else {
					pos += 2;  // jump over \r\n
					state = MPartReadingHeaders;
				}
			case MPartReadingHeaders:
				var b = buf.indexOf("\r\n\r\n", pos);
				if (b >= 0) {
					while (pos < b && !startsWith(buf, "Content-Disposition:", pos)) {
						pos = buf.indexOf("\r\n", pos) + 2;  // jump over \r\n
					}
					if (!startsWith(buf, "Content-Disposition:", pos)) {
						throw "Assert failed: part missing a `Content-Disposition` header";
					}
					var fn = buf.indexOf("filename=", pos);
					if (fn > 0 && fn < b) {
						fn += 9;
						var q = buf.charAt(fn++);
						// trace('filename=buf.substring(fn, buf.indexOf(q, fn))');
						add({ code:CPartFilename, buffer:buf, start:fn, length:(buf.indexOf(q, fn) - fn) });
					}
					var n = buf.indexOf("name=", pos);
					if (n > 0 && fn > 0 && n == fn - 6)
						n = buf.indexOf("name=", fn + 1);
					if (n > 0 && n < b) {
						n += 5;
						var q = buf.charAt(n++);
						// trace('name=buf.substring(n, buf.indexOf(q, n))');
						add({ code:CPartKey, buffer:buf, start:n, length:(buf.indexOf(q, n) - n) });
					}
					pos = b + 4;  // jump over \r\n\r\n
					state = MPartReadingData;
					break;
				}
				return null;
			case MPartReadingData:
				var b = buf.indexOf(boundary, pos);
				if (b >= 0) {
					while (pos < b - 2) {  // remove trailling \r\n
						var len = b - 2 - pos;
						if (len > outputSize)
							len = outputSize;
						add({ code:CPartData, buffer:buf, start:pos, length:len });
						pos += len;
					}
					add({ code:CPartDone, buffer:null, start:0, length:0 });
					pos = b + boundary.length;  // jump over boundary but not \r\n
					state = MPartInit;
					break;
				} else {
					b = buf.indexOf("\r\n--", pos);
					if (pos >= buf.length)
						break;  // fetch more data, please
					if (b < 0 || !startsWith(boundary, buf.substr(pos + 2, boundary.length))) {
						while (pos < buf.length) {
							var len = buf.length - pos;
							if (len > outputSize)
								len = outputSize;
							add({ code:CPartData, buffer:buf, start:pos, length:len });
							pos += len;
						}
						break;
					}
				}
			case MFinished:
				buf = null;
				pos = -1;
				add({ code:CExecute, buffer:null, start:0, length:0 });
				break;
			}
		}
		return pop();
	}

	function pop()
	{
		if (queue != null) {
			var m = queue;
			queue = queue.next;
			m.next = null;
			return m;
		}
		return null;
	}

	function add(m:MultipartMessage)
	{
		if (m.next != null)
			throw "Assert failed: `m.next` set by caller";
		if (queue == null) {
			queue = m;
			return;
		}
		var last = queue;
		while (last.next != null)
			last = last.next;
		last.next = m;
	}

	inline function startsWith(buffer:String, start:String, ?bufPos=0)
	{
		return buffer.length >= bufPos + start.length && buffer.substr(bufPos, start.length) == start;
	}
}

