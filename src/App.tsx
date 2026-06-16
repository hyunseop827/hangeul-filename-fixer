import { useEffect, useMemo, useState } from "react";
import type { PlanInput, PlanResult } from "../electron/filename";

type Status = {
  tone: "success" | "error" | "info";
  message: string;
};

const forbiddenCharacters = /[<>:"/\\|?*\u0000-\u001f]/g;
const reservedDeviceNames = new Set([
  "CON",
  "PRN",
  "AUX",
  "NUL",
  ...Array.from({ length: 9 }, (_, index) => `COM${index + 1}`),
  ...Array.from({ length: 9 }, (_, index) => `LPT${index + 1}`)
]);

const choseongPreview = [
  "ㄱ",
  "ㄲ",
  "ㄴ",
  "ㄷ",
  "ㄸ",
  "ㄹ",
  "ㅁ",
  "ㅂ",
  "ㅃ",
  "ㅅ",
  "ㅆ",
  "ㅇ",
  "ㅈ",
  "ㅉ",
  "ㅊ",
  "ㅋ",
  "ㅌ",
  "ㅍ",
  "ㅎ"
];
const jungseongPreview = [
  "ㅏ",
  "ㅐ",
  "ㅑ",
  "ㅒ",
  "ㅓ",
  "ㅔ",
  "ㅕ",
  "ㅖ",
  "ㅗ",
  "ㅘ",
  "ㅙ",
  "ㅚ",
  "ㅛ",
  "ㅜ",
  "ㅝ",
  "ㅞ",
  "ㅟ",
  "ㅠ",
  "ㅡ",
  "ㅢ",
  "ㅣ"
];
const jongseongPreview = [
  "ㄱ",
  "ㄲ",
  "ㄳ",
  "ㄴ",
  "ㄵ",
  "ㄶ",
  "ㄷ",
  "ㄹ",
  "ㄺ",
  "ㄻ",
  "ㄼ",
  "ㄽ",
  "ㄾ",
  "ㄿ",
  "ㅀ",
  "ㅁ",
  "ㅂ",
  "ㅄ",
  "ㅅ",
  "ㅆ",
  "ㅇ",
  "ㅈ",
  "ㅊ",
  "ㅋ",
  "ㅌ",
  "ㅍ",
  "ㅎ"
];

function App() {
  const [sourcePath, setSourcePath] = useState<string | null>(null);
  const [baseName, setBaseName] = useState("");
  const [keepOriginalName, setKeepOriginalName] = useState(true);
  const [outputDirectory, setOutputDirectory] = useState<string | null>(null);
  const [preview, setPreview] = useState<PlanResult>({ plans: [], rejectedPaths: [] });
  const [createdPath, setCreatedPath] = useState<string | null>(null);
  const [status, setStatus] = useState<Status | null>(null);
  const [isDragging, setIsDragging] = useState(false);

  const sourceName = sourcePath ? baseNameFromPath(sourcePath) : "";
  const sourceParts = splitFileName(sourceName);
  const sourceSafeStem = sourceName ? windowsSafeStem(sourceParts.stem) : "";
  const windowsCompatibleName = sourceName
    ? `${sourceSafeStem}${sourceParts.extension}`
    : "";
  const windowsOriginalName = sourceName ? windowsOriginalDisplayPreview(sourceName) : "";
  const customNameMissing = !keepOriginalName && baseName.trim().length === 0;
  const effectiveBaseName = keepOriginalName ? "" : baseName;

  const input: PlanInput | null = useMemo(() => {
    if (!sourcePath || !outputDirectory) {
      return null;
    }

    return {
      sourcePaths: [sourcePath],
      outputDirectory,
      baseName: effectiveBaseName
    };
  }, [effectiveBaseName, outputDirectory, sourcePath]);

  useEffect(() => {
    let isCancelled = false;

    async function refreshPreview() {
      if (!input) {
        setPreview({ plans: [], rejectedPaths: [] });
        return;
      }

      const nextPreview = await window.hangeulFilenameFixer.preview(input);
      if (!isCancelled) {
        setPreview(nextPreview);
      }
    }

    void refreshPreview();

    return () => {
      isCancelled = true;
    };
  }, [input]);

  const currentPlan = preview.plans[0] ?? null;
  const resultName = customNameMissing ? "" : currentPlan?.destinationName ?? "";
  const canConvert = Boolean(currentPlan && outputDirectory && !customNameMissing);

  async function selectFile() {
    const paths = await window.hangeulFilenameFixer.selectFiles();
    setFile(paths[0]);
  }

  async function selectOutputDirectory() {
    const directory = await window.hangeulFilenameFixer.selectOutputDirectory();
    if (directory) {
      setOutputDirectory(directory);
      setCreatedPath(null);
      setStatus(null);
    }
  }

  function setFile(nextPath: string | undefined) {
    if (!nextPath) {
      return;
    }

    setSourcePath(nextPath);
    setOutputDirectory(directoryFromPath(nextPath));
    setBaseName("");
    setCreatedPath(null);
    setStatus(null);
  }

  function handleDrop(event: React.DragEvent<HTMLDivElement>) {
    event.preventDefault();
    setIsDragging(false);

    const [firstFile] = Array.from(event.dataTransfer.files);
    if (!firstFile) {
      return;
    }

    setFile(window.hangeulFilenameFixer.getPathForFile(firstFile));

    if (event.dataTransfer.files.length > 1) {
      setStatus({ tone: "info", message: "파일 하나만 처리합니다. 첫 번째 파일만 선택했습니다." });
    }
  }

  function useOriginalName() {
    setKeepOriginalName(true);
    setCreatedPath(null);
    setStatus(null);
  }

  function useRenameMode() {
    setKeepOriginalName(false);
    setCreatedPath(null);
    setStatus(null);
  }

  async function convertFile() {
    if (!input || customNameMissing) {
      return;
    }

    try {
      const result = await window.hangeulFilenameFixer.convert(input);
      const destination = result.plans[0]?.destinationPath ?? null;
      setPreview(result);
      setCreatedPath(destination);
      setStatus({
        tone: "success",
        message: "완료되었습니다. 원본은 그대로 두고 사본을 만들었습니다."
      });
    } catch {
      setCreatedPath(null);
      setStatus({
        tone: "error",
        message: "파일을 만들 수 없습니다. 저장 위치 권한이나 파일명을 확인하세요."
      });
    }
  }

  function clearFile() {
    setSourcePath(null);
    setOutputDirectory(null);
    setPreview({ plans: [], rejectedPaths: [] });
    setCreatedPath(null);
    setStatus(null);
  }

  return (
    <main className="app-frame">
      {!sourcePath ? (
        <>
          <DropZone
            isDragging={isDragging}
            onSelectFile={selectFile}
            onDrop={handleDrop}
            onDragStateChange={setIsDragging}
          />
          <footer className="quiet-footer">분리된 한글 파일명을 Windows 호환 이름으로 정리합니다.</footer>
        </>
      ) : (
        <section className="detail-screen">
          <button type="button" className="back-button" onClick={clearFile}>
            ← 다른 파일 선택
          </button>

          <div className="section-label">선택된 파일</div>

          <FilenameCard
            fileName={sourceName}
            label="macOS Finder에서 보이는 이름"
            name={sourceName}
            description="MacOS 현재 원본"
          />

          <div className="flow-arrow">↓</div>

          <FilenameCard
            fileName={sourceName}
            label="Windows에서 보이는 이름"
            name={windowsOriginalName}
          />

          <div className="flow-arrow">↓</div>

          <FilenameCard
            fileName={windowsCompatibleName}
            label="변환 후 Windows 호환 이름"
            name={windowsCompatibleName}
            description="변환후 Windows 예상"
          />

          <div className="section-label output-label">출력 이름</div>
          <div className="segmented-control">
            <button
              type="button"
              className={keepOriginalName ? "active" : ""}
              onClick={useOriginalName}
            >
              기존 이름 유지
            </button>
            <button
              type="button"
              className={!keepOriginalName ? "active" : ""}
              onClick={useRenameMode}
            >
              이름 바꾸기
            </button>
          </div>

          <label className="rename-field">
            <span>새 파일명</span>
            <input
              value={baseName}
              onChange={(event) => {
                setBaseName(event.target.value);
                setCreatedPath(null);
              }}
              disabled={keepOriginalName}
              placeholder="확장자명을 제외하고 입력해주세요"
            />
          </label>

          <div className="section-label">결과</div>
          <div className="result-box">
            <span>생성될 사본 이름</span>
            <strong>{resultName ?? "저장 위치를 확인하는 중입니다."}</strong>
            <small>{outputDirectory ?? "원본 폴더"}</small>
          </div>

          <div className="actions">
            <button type="button" className="secondary-action" onClick={selectOutputDirectory}>
              저장 위치 변경
            </button>
            <button type="button" className="primary-action" disabled={!canConvert} onClick={convertFile}>
              Windows 호환 사본 만들기
            </button>
          </div>

          <div className="result-actions">
            {status ? (
              <p className={`status ${status?.tone ?? "info"}`}>
                {status.message}
              </p>
            ) : (
              <span aria-hidden="true" />
            )}
            <button
              type="button"
              className="finder-button"
              disabled={!createdPath}
              onClick={() => createdPath && void window.hangeulFilenameFixer.reveal([createdPath])}
            >
              Finder에서 보기
            </button>
          </div>
        </section>
      )}
    </main>
  );
}

function DropZone({
  isDragging,
  onSelectFile,
  onDrop,
  onDragStateChange
}: {
  isDragging: boolean;
  onSelectFile: () => void;
  onDrop: (event: React.DragEvent<HTMLDivElement>) => void;
  onDragStateChange: (isDragging: boolean) => void;
}) {
  return (
    <section
      className={`drop-zone ${isDragging ? "is-dragging" : ""}`}
      role="button"
      tabIndex={0}
      onClick={onSelectFile}
      onKeyDown={(event) => {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          onSelectFile();
        }
      }}
      onDragEnter={(event) => {
        event.preventDefault();
        onDragStateChange(true);
      }}
      onDragOver={(event) => event.preventDefault()}
      onDragLeave={() => onDragStateChange(false)}
      onDrop={onDrop}
    >
      <div className="upload-icon" aria-hidden="true">
        ⇧
      </div>
      <strong>파일을 여기에 놓기</strong>
      <span>또는 클릭해서 선택하세요. 한 번에 파일 하나만 처리합니다.</span>
    </section>
  );
}

function FilenameCard({
  fileName,
  label,
  name,
  description
}: {
  fileName: string;
  label: string;
  name: string;
  description?: string;
}) {
  const fileIcon = getFileIcon(fileName);

  return (
    <div className="filename-card">
      <FileIcon fileIcon={fileIcon} />
      <div className="filename-content">
        <div className="filename-meta">
          <span>{label}</span>
        </div>
        <strong>{name}</strong>
        {description ? <small>{description}</small> : null}
      </div>
    </div>
  );
}

function FileIcon({
  fileIcon
}: {
  fileIcon: {
    label: string;
    className: string;
    title: string;
    src?: string;
  };
}) {
  const [imageFailed, setImageFailed] = useState(false);
  const showImage = fileIcon.src && !imageFailed;

  return (
    <div className={`file-icon ${fileIcon.className}`} title={fileIcon.title} aria-hidden="true">
      {showImage ? <img src={fileIcon.src} alt="" onError={() => setImageFailed(true)} /> : fileIcon.label}
    </div>
  );
}

function getFileIcon(fileName: string) {
  const extension = splitFileName(fileName).extension.slice(1).toLowerCase();

  if (["doc", "docx"].includes(extension)) {
    return {
      label: "DOC",
      className: "word",
      title: "Word 문서",
      src: fileIconPath("word.svg")
    };
  }
  if (["hwp", "hwpx"].includes(extension)) {
    return {
      label: "HWP",
      className: "hwp",
      title: "한글 문서",
      src: fileIconPath("hwp.svg")
    };
  }
  if (extension === "pdf") {
    return {
      label: "PDF",
      className: "pdf",
      title: "PDF 문서",
      src: fileIconPath("pdf.svg")
    };
  }
  if (["ppt", "pptx"].includes(extension)) {
    return {
      label: "PPT",
      className: "ppt",
      title: "PowerPoint 문서",
      src: fileIconPath("powerpoint.svg")
    };
  }
  if (["xls", "xlsx", "csv"].includes(extension)) {
    return {
      label: "XLS",
      className: "sheet",
      title: "스프레드시트",
      src: fileIconPath("excel.svg")
    };
  }
  if (["txt", "md", "rtf"].includes(extension)) {
    return {
      label: "TXT",
      className: "text",
      title: "텍스트 문서",
      src: fileIconPath("text.svg")
    };
  }
  if (["png", "jpg", "jpeg", "gif", "webp", "heic", "svg"].includes(extension)) {
    return {
      label: "IMG",
      className: "image",
      title: "이미지 파일",
      src: fileIconPath("image.svg")
    };
  }
  if (["zip", "rar", "7z", "tar", "gz"].includes(extension)) {
    return {
      label: "ZIP",
      className: "archive",
      title: "압축 파일",
      src: fileIconPath("archive.svg")
    };
  }
  return {
    label: "FILE",
    className: "generic",
    title: "일반 파일",
    src: fileIconPath("generic.svg")
  };
}

function fileIconPath(fileName: string) {
  return `./file-icons/${fileName}`;
}

function windowsSafeStem(rawValue: string): string {
  let result = rawValue
    .normalize("NFC")
    .replace(forbiddenCharacters, "_")
    .trim();

  while (result.endsWith(".") || result.endsWith(" ")) {
    result = result.slice(0, -1);
  }

  if (result.length === 0) {
    result = "파일";
  }

  if (reservedDeviceNames.has(result.toUpperCase())) {
    result = `_${result}`;
  }

  return result.normalize("NFC");
}

function windowsOriginalDisplayPreview(value: string): string {
  let result = "";

  for (const character of value) {
    const codePoint = character.codePointAt(0) ?? 0;

    if (codePoint >= 0x1100 && codePoint <= 0x1112) {
      result += choseongPreview[codePoint - 0x1100];
      continue;
    }
    if (codePoint >= 0x1161 && codePoint <= 0x1175) {
      result += jungseongPreview[codePoint - 0x1161];
      continue;
    }
    if (codePoint >= 0x11a8 && codePoint <= 0x11c2) {
      result += jongseongPreview[codePoint - 0x11a8];
      continue;
    }

    result += character;
  }

  return result;
}

function splitFileName(fileName: string) {
  const dotIndex = fileName.lastIndexOf(".");
  if (dotIndex <= 0) {
    return { stem: fileName, extension: "" };
  }

  return {
    stem: fileName.slice(0, dotIndex),
    extension: fileName.slice(dotIndex)
  };
}

function baseNameFromPath(filePath: string) {
  return filePath.split(/[\\/]/).at(-1) ?? filePath;
}

function directoryFromPath(filePath: string) {
  const separatorIndex = Math.max(filePath.lastIndexOf("/"), filePath.lastIndexOf("\\"));
  return separatorIndex >= 0 ? filePath.slice(0, separatorIndex) : "";
}

export default App;
