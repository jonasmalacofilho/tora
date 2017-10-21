package fcgi;

import haxe.io.Bytes;
import neko.NativeString;
import tora.Code;
using StringTools;

enum MultipartState {
	MBeforeFirstBoundary;
	MAtBoundary;
	MPartReadingHeaders;
	MPartReadingData;
	MFinished;
}

typedef MultipartMessage = {
	code:Code,
	buffer:Null<String>,
	start:Int,
	length:Int,
	?next:Null<MultipartMessage>
}

/*
Streaming parser for multipart/form-data

Mostly based on RFC 7578: https://tools.ietf.org/html/rfc7578
*/
class MultipartParser {
	public var boundary(default,null):String;
	public var outputSize = 1 << 16;

	var state = MBeforeFirstBoundary;
	var pos = 0;
	var buf:String;  // might be null MBeforeFirstBoundary or when MFinished
	var queue:MultipartMessage;

	public function new(boundary)
	{
		this.boundary = boundary;
	}

	/*
	Feed the parser more data

	While this can be called as much as wanted, it is recommended to call it only
	once the parser has exhausted reading from its current buffer.

	Once MFinished, no additional data will be stored.
	*/
	public function feed(s:String):Void
	{
		if (state == MFinished)
			return;
		if (buf != null && pos < buf.length) {
			var curlen = buf.length - pos;
			var b = Bytes.alloc(curlen + s.length);
			b.blit(0, Bytes.ofData(NativeString.ofString(buf)), pos, curlen);
			b.blit(curlen, Bytes.ofData(NativeString.ofString(s)), 0, s.length);
			buf = NativeString.toString(b.getData());
		} else {
			buf = s;
		}
		pos = 0;
	}

	/*
	Parse multipart/form-data

	Returns a recipe for a Tora buffer message or `null`, if more data is needed.
	If done reading – if the closing boundary delimiter has been found – will
	continously return `CExecute`.
	*/
	public function read():MultipartMessage
	{
		while (queue == null) {
			switch state {
			case MBeforeFirstBoundary if (buf != null):  // buf might still be null MBeforeFirstBoundary
				var b = buf.indexOf(boundary, pos);
				if (b < 0)
					return null;
				pos = b + boundary.length;  // jump over boundary but not \r\n (or, possibly, --)
				state = MAtBoundary;
			case MAtBoundary if (pos + 2 <= buf.length):  // buf must have room for \r\n or --
				if (bufMatches("--", pos)) {
					pos = 0;
					buf = null;
					state = MFinished;
				} else {
					pos += 2;  // jump over \r\n
					state = MPartReadingHeaders;
				}
			case MPartReadingHeaders:
				var b = buf.indexOf("\r\n\r\n", pos);
				if (b < 0)
					return null;
				while (pos < b && !bufMatches("content-disposition:", pos, true))
					pos = buf.indexOf("\r\n", pos) + 2;  // jump over \r\n
				if (pos >= b)
					throw "Part missing a `Content-Disposition` header";
				var filename = null, name = null;
				while (pos < b && (name == null || filename == null)) {
					var eq = buf.indexOf("=", pos);
					if (eq >= 8 && bufMatches("filename", eq - 8))
						filename = readFieldValue(CPartFilename, eq + 1, b);  // updates pos
					else if (eq >= 8 && bufMatches("name", eq - 4))
						name = readFieldValue(CPartKey, eq + 1, b);  // updates pos
					else if (eq >= 0)
						pos = eq + 1;  // jump over =
					else
						break;
				}
				if (name == null)
					throw "Part disposition missing a `name` field";
				if (filename != null)
					add(filename);
				add(name);
				pos = b + 4;  // jump over \r\n\r\n
				state = MPartReadingData;
			case MPartReadingData if (pos < buf.length):  // if there's data to read already
				var b = -1;
				var end = pos;
				while (end < buf.length && end - pos < outputSize) {
					var pb = buf.indexOf("\r\n", end);  // possible boundary line ahead
					if (pb < 0) {
						end = buf.length;
						break;
					}
					if (pb + 2 + boundary.length > buf.length) {
						end = pb;
						break;
					}
					if (bufMatches(boundary, pb + 2)) {
						b = pb + 2;
						end = pb;
						break;
					}
					end = pb + 2;
				}
				while (pos < end) {
					var len = end - pos;
					if (len > outputSize)
						len = outputSize;
					add({ code:CPartData, buffer:buf, start:pos, length:len });
					pos += len;
				}
				if (b >= 0) {
					add({ code:CPartDone, buffer:null, start:0, length:0 });
					pos = b + boundary.length;  // jump over boundary but not \r\n
					state = MAtBoundary;
				}
				// we have queued messages or need more data to continue;
				// either way, return control to the caller
				break;

			case MFinished:
				add({ code:CExecute, buffer:null, start:0, length:0 });
			case _:  // not enough data buffered to continue
				return null;
			}
		}
		return pop();
	}

	function pop()
	{
		if (queue == null)
			return null;
		var m = queue;
		queue = queue.next;
		m.next = null;
		return m;
	}

	function add(m:MultipartMessage)
	{
		if (m.next != null)
			throw "Assert failed: `m.next` set by caller";
		if (queue == null) {
			queue = m;
		} else {
			var last = queue;
			while (last.next != null)
				last = last.next;
			last.next = m;
		}
	}

	static inline function imatch(a:Int, b:Int)
		return (a >= "A".code && a <= "Z".code ? a|32 : a) == (b >= "A".code && b <= "Z".code ? b|32 : b);

	function bufMatches(sub:String, at:Int, caseInsensitive=false)
	{
		if (buf.length - at < sub.length)
			return false;
		var i = 0;
		if (caseInsensitive) {
			while (i < sub.length && imatch(sub.fastCodeAt(i), buf.fastCodeAt(at + i))) i++;
		} else {
			while (i < sub.length && sub.fastCodeAt(i) == buf.fastCodeAt(at + i)) i++;
		}
		return i == sub.length;
	}

	function readFieldValue(code:Code, startAt:Int, maxPos:Int):MultipartMessage
	{
		var quote = buf.charAt(startAt);
		if (quote == "\"") {
			var endAt = buf.indexOf(quote, ++startAt);
			if (endAt < 0 && endAt > maxPos)
				throw "Unterminated field";
			pos = endAt + 1;
			return { code:code, buffer:buf, start:startAt, length:(endAt - startAt) };
		} else {
			throw "Assert failed: unquoted field value or unexpected encoding";
		}
	}
}

