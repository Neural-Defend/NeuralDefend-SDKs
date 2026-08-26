package neuraldefend

import (
	"bytes"
	"io"
	"os"
	"path/filepath"
	"strings"
)

const (
	// IMAGE_MAX_BYTES is the maximum upload size for image detection.
	IMAGE_MAX_BYTES = 10 * 1024 * 1024
	// VIDEO_MAX_BYTES is the maximum upload size for video detection.
	VIDEO_MAX_BYTES = 1_500_000_000
)

var imageMIMETypes = map[string]string{
	".jpg":  "image/jpeg",
	".jpeg": "image/jpeg",
	".png":  "image/png",
	".bmp":  "image/bmp",
	".tif":  "image/tiff",
	".tiff": "image/tiff",
	".webp": "image/webp",
	".heic": "image/heic",
	".heif": "image/heif",
}

var videoMIMETypes = map[string]string{
	".mp4":  "video/mp4",
	".avi":  "video/vnd.avi",
	".mov":  "video/quicktime",
	".mkv":  "video/matroska",
	".wmv":  "video/x-ms-wmv",
	".flv":  "video/x-flv",
	".webm": "video/webm",
	".ogg":  "video/ogg",
	".ogv":  "video/ogg",
}

var mimeTypes = mergeMIME(imageMIMETypes, videoMIMETypes)

// ImageExtensions lists supported image file extensions including the leading dot.
var ImageExtensions = keys(imageMIMETypes)

// VideoExtensions lists supported video file extensions including the leading dot.
var VideoExtensions = keys(videoMIMETypes)

type mediaKind int

const (
	mediaKindImage mediaKind = iota
	mediaKindVideo
)

// Media describes upload input for DetectImage and DetectVideo.
type Media struct {
	filename string

	path   string
	data   []byte
	reader io.Reader
	size   int64
	prefix []byte
	seeker io.ReadSeeker
	closer io.Closer
}

// FileMedia builds media from a readable regular file path.
func FileMedia(path string) Media {
	return Media{path: path}
}

// BytesMedia builds media from an in-memory byte slice.
func BytesMedia(name string, data []byte) Media {
	return Media{filename: name, data: data}
}

// ReaderMedia builds media from a reader. When size is negative the stream is treated
// as non-seekable and the client must use MaxRetries=0.
func ReaderMedia(name string, r io.Reader, size int64) Media {
	return Media{filename: name, reader: r, size: size}
}

func (m Media) withKind(kind mediaKind, maxBytes int64, extensions map[string]struct{}) (*preparedUpload, error) {
	selectedName := strings.TrimSpace(m.filename)
	if m.path != "" {
		info, err := os.Stat(m.path)
		if err != nil {
			return nil, &ValidationError{Detail: "file path does not exist or is not readable"}
		}
		if info.IsDir() {
			return nil, &ValidationError{Detail: "file path must reference a regular file"}
		}
		if info.Size() == 0 {
			return nil, &ValidationError{Detail: "file must not be empty"}
		}
		if info.Size() > maxBytes {
			return nil, &ValidationError{Detail: "file exceeds the endpoint size limit"}
		}
		if selectedName == "" {
			selectedName = filepath.Base(m.path)
		}
		file, err := os.Open(m.path)
		if err != nil {
			return nil, &ValidationError{Detail: "file path does not exist or is not readable"}
		}
		return newPreparedUpload(selectedName, maxBytes, file, file, int64(0), nil, true, extensions)
	}

	if m.data != nil {
		if len(m.data) == 0 {
			return nil, &ValidationError{Detail: "file must not be empty"}
		}
		if int64(len(m.data)) > maxBytes {
			return nil, &ValidationError{Detail: "file exceeds the endpoint size limit"}
		}
		if selectedName == "" {
			return nil, &ValidationError{Detail: "filename is required when uploading bytes"}
		}
		return newPreparedUpload(selectedName, maxBytes, nil, nil, 0, m.data, false, extensions)
	}

	if m.reader != nil {
		if selectedName == "" {
			return nil, &ValidationError{Detail: "filename is required for a nameless file-like object"}
		}
		if seeker, ok := m.reader.(io.ReadSeeker); ok && m.size >= 0 {
			end, err := seekEnd(seeker)
			if err != nil {
				return nil, &ValidationError{Detail: "file-like object must support seek() and tell()"}
			}
			if end <= 0 {
				return nil, &ValidationError{Detail: "file must not be empty"}
			}
			if end > maxBytes {
				return nil, &ValidationError{Detail: "file exceeds the endpoint size limit"}
			}
			if _, err := seeker.Seek(0, io.SeekStart); err != nil {
				return nil, &ValidationError{Detail: "file-like object must support seek() and tell()"}
			}
			var closer io.Closer
			if c, ok := m.reader.(io.Closer); ok {
				closer = c
			}
			return newPreparedUpload(selectedName, maxBytes, m.reader, seeker, 0, nil, closer != nil, extensions)
		}
		if m.size >= 0 {
			if m.size == 0 {
				return nil, &ValidationError{Detail: "file must not be empty"}
			}
			if m.size > maxBytes {
				return nil, &ValidationError{Detail: "file exceeds the endpoint size limit"}
			}
		}
		prefix := make([]byte, 1)
		n, err := io.ReadFull(m.reader, prefix)
		if err != nil && err != io.EOF && err != io.ErrUnexpectedEOF {
			return nil, &ValidationError{Detail: "file-like object is not readable"}
		}
		if n == 0 {
			return nil, &ValidationError{Detail: "file must not be empty"}
		}
		prefix = prefix[:n]
		var closer io.Closer
		if c, ok := m.reader.(io.Closer); ok {
			closer = c
		}
		return newPreparedUpload(selectedName, maxBytes, m.reader, nil, 0, nil, closer != nil, extensions, prefix)
	}

	return nil, &ValidationError{Detail: "file must be a path, bytes, or binary file-like object"}
}

type preparedUpload struct {
	filename    string
	maxBytes    int64
	data        []byte
	stream      io.Reader
	seeker      io.ReadSeeker
	initialPos  int64
	prefix      []byte
	ownsStream  bool
	extensions  map[string]struct{}
	unsupported bool
}

func newPreparedUpload(
	filename string,
	maxBytes int64,
	stream io.Reader,
	seeker io.ReadSeeker,
	initialPos int64,
	data []byte,
	ownsStream bool,
	extensions map[string]struct{},
	prefix ...[]byte,
) (*preparedUpload, error) {
	ext := strings.ToLower(filepath.Ext(filename))
	_, supported := extensions[ext]
	u := &preparedUpload{
		filename:    filename,
		maxBytes:    maxBytes,
		data:        data,
		stream:      stream,
		seeker:      seeker,
		initialPos:  initialPos,
		ownsStream:  ownsStream,
		extensions:  extensions,
		unsupported: ext != "" && !supported,
	}
	if len(prefix) > 0 {
		u.prefix = prefix[0]
	}
	return u, nil
}

func (u *preparedUpload) openAttempt() (io.Reader, error) {
	if u.data != nil {
		return bytes.NewReader(u.data), nil
	}
	if u.seeker != nil {
		if _, err := u.seeker.Seek(u.initialPos, io.SeekStart); err != nil {
			return nil, &ValidationError{Detail: "file-like object could not be rewound for retry"}
		}
		return u.seeker, nil
	}
	if u.stream == nil {
		return nil, &ValidationError{Detail: "invalid upload source"}
	}
	return &limitedReader{source: u.stream, prefix: u.prefix, limit: u.maxBytes}, nil
}

func (u *preparedUpload) close() {
	if u.ownsStream {
		if closer, ok := u.stream.(io.Closer); ok {
			_ = closer.Close()
		}
	}
}

type limitedReader struct {
	source io.Reader
	prefix []byte
	offset int
	limit  int64
	count  int64
}

func (r *limitedReader) Read(p []byte) (int, error) {
	if len(p) == 0 {
		return 0, nil
	}
	var out []byte
	remaining := len(p)

	if r.offset < len(r.prefix) {
		n := copy(p, r.prefix[r.offset:])
		r.offset += n
		out = append(out, p[:n]...)
		remaining -= n
		if remaining == 0 {
			r.count += int64(len(out))
			if r.count > r.limit {
				return len(out), &ValidationError{Detail: "file exceeds the endpoint size limit"}
			}
			return len(out), nil
		}
		p = p[n:]
	}

	n, err := r.source.Read(p[:remaining])
	if n > 0 {
		out = append(out, p[:n]...)
	}
	r.count += int64(len(out))
	if r.count > r.limit {
		return len(out), &ValidationError{Detail: "file exceeds the endpoint size limit"}
	}
	return len(out), err
}

func MIMEForFilename(filename string) string {
	ext := strings.ToLower(filepath.Ext(filename))
	if mime, ok := mimeTypes[ext]; ok {
		return mime
	}
	return "application/octet-stream"
}

func mergeMIME(parts ...map[string]string) map[string]string {
	out := make(map[string]string)
	for _, part := range parts {
		for k, v := range part {
			out[k] = v
		}
	}
	return out
}

func keys(m map[string]string) map[string]struct{} {
	out := make(map[string]struct{}, len(m))
	for k := range m {
		out[k] = struct{}{}
	}
	return out
}

func seekEnd(seeker io.ReadSeeker) (int64, error) {
	current, err := seeker.Seek(0, io.SeekCurrent)
	if err != nil {
		return 0, err
	}
	end, err := seeker.Seek(0, io.SeekEnd)
	if err != nil {
		return 0, err
	}
	if _, err := seeker.Seek(current, io.SeekStart); err != nil {
		return 0, err
	}
	return end - current, nil
}

func imageExtensions() map[string]struct{} {
	return ImageExtensions
}

func videoExtensions() map[string]struct{} {
	return VideoExtensions
}
