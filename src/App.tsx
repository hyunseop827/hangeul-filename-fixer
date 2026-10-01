import { useEffect, useMemo, useState } from "react";
import { notRegularFileMessage, type FileCopyPlan, type PlanInput } from "../electron/api";
import { decomposedDisplayName, splitFileName, windowsSafeFileName } from "../electron/naming";

type Status = {
  tone: "success" | "error" | "info";
  message: string;
};

type NameMode = "keep" | "rename";

type FileIconType = {
  extensions: string[];
  label: string;
  className: string;
  title: string;
  svg: string;
};

const fileIconTypes: FileIconType[] = [
  { extensions: ["doc", "docx"], label: "DOC", className: "word", title: "Word 문서", svg: "word.svg" },
  { extensions: ["hwp", "hwpx"], label: "HWP", className: "hwp", title: "한글 문서", svg: "hwp.svg" },
  { extensions: ["pdf"], label: "PDF", className: "pdf", title: "PDF 문서", svg: "pdf.svg" },
  { extensions: ["ppt", "pptx"], label: "PPT", className: "ppt", title: "PowerPoint 문서", svg: "powerpoint.svg" },
  { extensions: ["xls", "xlsx", "csv"], label: "XLS", className: "sheet", title: "스프레드시트", svg: "excel.svg" },
  { extensions: ["txt", "md", "rtf"], label: "TXT", className: "text", title: "텍스트 문서", svg: "text.svg" },
  {
    extensions: ["png", "jpg", "jpeg", "gif", "webp", "heic", "svg"],
    label: "IMG",
    className: "image",
    title: "이미지 파일",
    svg: "image.svg"
  },
  { extensions: ["zip", "rar", "7z", "tar", "gz"], label: "ZIP", className: "archive", title: "압축 파일", svg: "archive.svg" }
];

const genericFileIcon: FileIconType = {
  extensions: [],
  label: "FILE",
  className: "generic",
  title: "일반 파일",
  svg: "generic.svg"
};

function App() {
  const [sourcePath, setSourcePath] = useState<string | null>(null);
  const [baseName, setBaseName] = useState("");
  const [nameMode, setNameMode] = useState<NameMode>("keep");
  const [outputDirectory, setOutputDirectory] = useState<string | null>(null);
  // undefined while the preview for a new file is loading; null when the source is not a regular file.
  const [plan, setPlan] = useState<FileCopyPlan | null | undefined>(undefined);
  const [previewVersion, setPreviewVersion] = useState(0);
  const [createdPlan, setCreatedPlan] = useState<FileCopyPlan | null>(null);
  const [isConverting, setIsConverting] = useState(false);
  const [status, setStatus] = useState<Status | null>(null);
  const [isDragging, setIsDragging] = useState(false);

  // Prefer the name stored on disk: a dropped file's path is always decomposed (NFD).
  const sourceName = (createdPlan ?? plan)?.sourceName ?? (sourcePath ? baseNameFromPath(sourcePath) : "");
  const sourceParts = splitFileName(sourceName);
  const windowsCompatibleName = sourceName ? windowsSafeFileName(sourceParts.stem, sourceParts.extension) : "";
  const fileIcon = getFileIcon(sourceName);
  const customNameMissing = nameMode === "rename" && baseName.trim().length === 0;
  const effectiveBaseName = nameMode === "keep" ? "" : baseName;

  const input: PlanInput | null = useMemo(() => {
    if (!sourcePath || !outputDirectory) {
      return null;
    }

    return {
      sourcePath,
      outputDirectory,
      baseName: effectiveBaseName
    };
  }, [effectiveBaseName, outputDirectory, sourcePath]);

  useEffect(() => {
    if (!input) {
      return undefined;
    }

    let isCancelled = false;
    void window.hangeulFilenameFixer.preview(input).then((nextPlan) => {
      if (!isCancelled) {
        setPlan(nextPlan);
      }
    });

    return () => {
      isCancelled = true;
    };
  }, [input, previewVersion]);

  const canConvert = Boolean(input && plan) && !customNameMissing && !isConverting && !createdPlan;

  async function selectFile() {
    setFile(await window.hangeulFilenameFixer.selectFile());
  }

  async function selectOutputDirectory() {
    const directory = await window.hangeulFilenameFixer.selectOutputDirectory(outputDirectory ?? undefined);
    if (directory) {
      setOutputDirectory(directory);
      resetResult();
    }
  }

  function setFile(nextPath: string | null) {
    if (!nextPath) {
      return;
    }

    setSourcePath(nextPath);
    setOutputDirectory(directoryFromPath(nextPath));
    setBaseName("");
    setNameMode("keep");
    setPlan(undefined);
    setPreviewVersion((version) => version + 1);
    resetResult();
  }

  function resetResult() {
    setCreatedPlan(null);
    setStatus(null);
  }

  function handleDrop(event: React.DragEvent<HTMLDivElement>) {
    event.preventDefault();
    setIsDragging(false);

    const [firstFile] = Array.from(event.dataTransfer.files);
    if (!firstFile) {
      return;
    }

    setFile(window.hangeulFilenameFixer.getPathForFile(firstFile) || null);

    if (event.dataTransfer.files.length > 1) {
      setStatus({ tone: "info", message: "파일 하나만 처리합니다. 첫 번째 파일만 선택했습니다." });
    }
  }

  function changeNameMode(mode: NameMode) {
    setNameMode(mode);
    resetResult();
  }

  async function convertFile() {
    if (!input || !canConvert) {
      return;
    }

    setIsConverting(true);
    setStatus({ tone: "info", message: "사본을 만드는 중입니다…" });

    try {
      setCreatedPlan(await window.hangeulFilenameFixer.convert(input));
      setStatus({ tone: "success", message: "완료되었습니다. 저장된 파일명이 NFC인지 확인했습니다." });
    } catch (error) {
      setStatus({ tone: "error", message: ipcErrorMessage(error) });
    } finally {
      setIsConverting(false);
      // The new copy now takes its name, so the next preview needs a fresh " (n)".
      setPreviewVersion((version) => version + 1);
    }
  }

  function clearFile() {
    setSourcePath(null);
    setOutputDirectory(null);
    resetResult();
  }

  function resultName(): string {
    if (createdPlan) {
      return createdPlan.destinationName;
    }
    if (customNameMissing) {
      return "새 파일명을 입력하세요.";
    }
    if (plan === undefined) {
      return "저장 위치를 확인하는 중입니다.";
    }
    if (plan === null) {
      return notRegularFileMessage;
    }
    return plan.destinationName;
  }

  function resultHint(): string | null {
    if (createdPlan || customNameMissing || !plan) {
      return null;
    }
    if (nameMode === "keep" && windowsCompatibleName === sourceName) {
      return "이미 Windows 호환 이름이라 사본을 만들지 않아도 됩니다.";
    }
    if (plan.hasNumberSuffix) {
      return "같은 이름의 파일(원본 포함)이 있어 번호가 붙습니다. 원래 이름 그대로 받으려면 저장 위치를 변경하세요.";
    }
    return null;
  }

  const shownName = resultName();
  const isShowingFileName = Boolean(createdPlan || (plan && !customNameMissing));
  const hint = resultHint();

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
          <button type="button" className="back-button" onClick={clearFile} disabled={isConverting}>
            ← 다른 파일 선택
          </button>

          <div className="section-label">선택된 파일</div>

          <FilenameCard
            icon={fileIcon}
            label="macOS Finder에서 보이는 이름"
            // Finder shows a ":" in the stored name as "/".
            name={sourceName.replaceAll(":", "/")}
            description="macOS 현재 원본"
          />

          <div className="flow-arrow" aria-hidden="true">
            ↓
          </div>

          <FilenameCard icon={fileIcon} label="Windows에서 보일 수 있는 이름" name={decomposedDisplayName(sourceName)} />

          <div className="flow-arrow" aria-hidden="true">
            ↓
          </div>

          <FilenameCard
            icon={fileIcon}
            label="변환 후 Windows 호환 이름"
            name={windowsCompatibleName}
            description="변환 후 Windows 예상"
          />

          <div className="section-label output-label">출력 이름</div>
          <div className="segmented-control">
            <button
              type="button"
              className={nameMode === "keep" ? "active" : ""}
              aria-pressed={nameMode === "keep"}
              disabled={isConverting}
              onClick={() => changeNameMode("keep")}
            >
              기존 이름 유지
            </button>
            <button
              type="button"
              className={nameMode === "rename" ? "active" : ""}
              aria-pressed={nameMode === "rename"}
              disabled={isConverting}
              onClick={() => changeNameMode("rename")}
            >
              이름 바꾸기
            </button>
          </div>

          <label className="rename-field">
            <span>새 파일명</span>
            <input
              value={nameMode === "rename" ? baseName : ""}
              onChange={(event) => {
                setBaseName(event.target.value);
                resetResult();
              }}
              disabled={nameMode !== "rename" || isConverting}
              placeholder="확장자명을 제외하고 입력해주세요"
              spellCheck={false}
            />
          </label>

          <div className="section-label">결과</div>
          <div className="result-box">
            <span>{createdPlan ? "생성된 사본" : "생성될 사본 이름"}</span>
            <strong className={isShowingFileName ? undefined : "is-message"} title={shownName}>
              {shownName}
            </strong>
            <small title={outputDirectory ?? undefined}>{outputDirectory}</small>
            {hint ? <p className="result-hint">{hint}</p> : null}
          </div>

          <div className="actions">
            <button
              type="button"
              className="secondary-action"
              onClick={selectOutputDirectory}
              disabled={isConverting}
            >
              저장 위치 변경
            </button>
            <button type="button" className="primary-action" disabled={!canConvert} onClick={convertFile}>
              NFC 사본 만들기
            </button>
          </div>

          <div className="result-actions">
            <p className={status ? `status ${status.tone}` : "status"} role="status">
              {status?.message}
            </p>
            <button
              type="button"
              className="finder-button"
              disabled={!createdPlan}
              onClick={() => {
                if (createdPlan) {
                  void window.hangeulFilenameFixer.reveal(createdPlan.destinationPath);
                }
              }}
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
  icon,
  label,
  name,
  description
}: {
  icon: FileIconType;
  label: string;
  name: string;
  description?: string;
}) {
  return (
    <div className="filename-card">
      <FileIcon icon={icon} />
      <div className="filename-content">
        <div className="filename-meta">
          <span>{label}</span>
        </div>
        <strong title={name}>{name}</strong>
        {description ? <small>{description}</small> : null}
      </div>
    </div>
  );
}

function FileIcon({ icon }: { icon: FileIconType }) {
  const [imageFailed, setImageFailed] = useState(false);

  return (
    <div className={`file-icon ${icon.className}`} title={icon.title} aria-hidden="true">
      {imageFailed ? icon.label : <img src={`./file-icons/${icon.svg}`} alt="" onError={() => setImageFailed(true)} />}
    </div>
  );
}

function getFileIcon(fileName: string): FileIconType {
  const extension = splitFileName(fileName).extension.slice(1).toLowerCase();
  return fileIconTypes.find((type) => type.extensions.includes(extension)) ?? genericFileIcon;
}

// Electron wraps main-process errors as "Error invoking remote method 'x': Error: <message>".
function ipcErrorMessage(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  return message.replace(/^Error invoking remote method '[^']*': (?:Error: )?/, "");
}

function baseNameFromPath(filePath: string) {
  return filePath.slice(filePath.lastIndexOf("/") + 1);
}

function directoryFromPath(filePath: string) {
  return filePath.slice(0, filePath.lastIndexOf("/")) || "/";
}

export default App;
