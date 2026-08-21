//
//  AgentFileFailures.swift
//  Puck
//
//  What a file-tool failure says to the *model*, as opposed to the user.
//
//  Split from the message the editor pane shows (WorkspaceFileServiceError):
//  a person reading "파일을 찾을 수 없습니다" in the pane already knows what
//  they clicked, while a model that guessed a path needs telling what a path
//  is supposed to look like here -- otherwise it burns a turn discovering the
//  rule by trial (observed live: show_code called with a bare "AgentRunner.swift").
//

import Foundation

extension WorkspaceFileServiceError {
    /// The failure detail handed to the model.
    var agentDetail: String {
        switch code {
        case .fileNotFound, .invalidPath, .pathOutsideWorkspace:
            return message
                + " 경로는 프로젝트 루트 기준 상대 경로여야 해요 (예: src/App/main.swift)."
                + " 정확한 경로를 모르면 list_files로 확인한 뒤 다시 부르세요."
        case .fileConflict, .fileTooLarge, .binaryFile, .encodingError:
            // Nothing about the path would fix these, and a wrong suggestion
            // sends the model looking in the wrong place.
            return message
        }
    }
}

extension DispatchedToolResult {
    static func failed(_ detail: String) -> DispatchedToolResult {
        DispatchedToolResult(ok: false, data: nil, error: "execution_failed", detail: detail)
    }

    static func succeeded(detail: String?) -> DispatchedToolResult {
        DispatchedToolResult(ok: true, data: nil, error: nil, detail: detail)
    }
}
