import fcgi.MultipartParser;
import tora.Code;
import utest.Assert;

class TestFastCgiMultipart {
	public function new() {}

	// simplify a MultipartMessage for easier comparison
	static function s(msg:MultipartMessage)
	{
		if (msg == null)
			return null;
		var data = msg.buffer != null ? msg.buffer.substr(msg.start, msg.length).toString() : null;
		return { code:msg.code, data:data };
	}

	public function test_complete_flow_with_single_feeding()
	{
		var m = new MultipartParser("--foo");
		m.feed('garbage\r\n--foo\r\nContent-Disposition: form-data; name="foo"\r\n\r\nbar\r\n--foo--\r\ngarbage');
		Assert.same({ code:CPartKey, data:"foo" }, s(m.read()));
		Assert.same({ code:CPartData, data:"bar" }, s(m.read()));
		Assert.same({ code:CPartDone, data:null }, s(m.read()));
		Assert.same({ code:CExecute, data:null }, s(m.read()));
	}

	public function test_filenames()
	{
		var m = new MultipartParser("--foo");
		m.feed('garbage\r\n--foo\r\nContent-Disposition: form-data; name="foo"; filename="foo.png"\r\n\r\n');
		Assert.same({ code:CPartFilename, data:"foo.png" }, s(m.read()));
		Assert.same({ code:CPartKey, data:"foo" }, s(m.read()));

		var m = new MultipartParser("--foo");
		m.feed('garbage\r\n--foo\r\nContent-Disposition: form-data; filename="foo.png"; name="foo"\r\n\r\n');
		Assert.same({ code:CPartFilename, data:"foo.png" }, s(m.read()));
		Assert.same({ code:CPartKey, data:"foo" }, s(m.read()));
	}

	public function test_linebreaks_in_disposition()
	{
		var m = new MultipartParser("--foo");
		m.feed('garbage\r\n--foo\r\nContent-Disposition: form-data; name="foo";\r\n  filename="foo.png"\r\n\r\n');
		Assert.same({ code:CPartFilename, data:"foo.png" }, s(m.read()));
		Assert.same({ code:CPartKey, data:"foo" }, s(m.read()));
	}

	public function test_part_has_content_type()
	{
		var m = new MultipartParser("--foo");
		m.feed('garbage\r\n--foo\r\nContent-Disposition: form-data; name="foo"\r\nContent-Type: bar\r\n\r\n');
		Assert.same({ code:CPartKey, data:"foo" }, s(m.read()));

		var m = new MultipartParser("--foo");
		m.feed('garbage\r\n--foo\r\nContent-Type: bar\r\nContent-Disposition: form-data; name="foo"\r\n\r\n');
		Assert.same({ code:CPartKey, data:"foo" }, s(m.read()));
	}

	public function test_lowercase_header()
	{
		var m = new MultipartParser("--foo");
		m.feed('garbage\r\n--foo\r\ncontent-disposition: form-data; name="foo"\r\n\r\n');
		Assert.same({ code:CPartKey, data:"foo" }, s(m.read()));
	}

	public function test_read_data_with_buffer_breaks()
	{
		var m = new MultipartParser("--foo");
		m.feed('garbage\r\n--foo\r\nContent-Disposition: form-data; name="foo"\r\n\r\n');
		Assert.same({ code:CPartKey, data:"foo" }, s(m.read()));
		Assert.isNull(s(m.read()));

		m.feed('bar');
		Assert.same({ code:CPartData, data:"bar" }, s(m.read()));

		Assert.isNull(s(m.read()));

		m.feed('\r\n');
		Assert.isNull(s(m.read()));
		m.feed('-');
		Assert.isNull(s(m.read()));
		m.feed('-fo');
		Assert.isNull(s(m.read()));
		m.feed('ster');
		Assert.same({ code:CPartData, data:"\r\n--foster" }, s(m.read()));

		m.feed('\r\n--fo');
		Assert.isNull(s(m.read()));
		m.feed('o');
		Assert.same({ code:CPartDone, data:null }, s(m.read()));

		m.feed('--');
		Assert.same({ code:CExecute, data:null }, s(m.read()));
	}
}
