package fcgi;

enum MultipartState {
	MFinished;
	MBeforeFirstPart;
	MPartInit;
	MPartReadingHeaders;
	MPartReadingData;
}

