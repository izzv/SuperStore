//
//  ErrorProcessing.swift
//  SideStore
//
//  Created by Magesh K on 20/01/25.
//  Copyright © 2025 SideStore. All rights reserved.
//
class ErrorProcessing {
    enum InfoMode: String {
        case fullError
        case localizedDescription
    }
    let info: InfoMode
    let unique: Bool
    let recur: Bool
    var errors: Set<String> = []
    init(_ mode: InfoMode = .localizedDescription, unique: Bool = false, recur: Bool = false){
        self.info = mode
        self.unique = unique
        self.recur = recur
    }
    private func userFriendlyDescription(for error: NSError) -> String {
        let domain = error.domain
        if domain == "kcerrordomain" || domain == NSOSStatusErrorDomain {
            switch error.code {
            case -25300: 
                return NSLocalizedString("Keychain item not found.", comment: "")
            case -25299: 
                return NSLocalizedString("Keychain item already exists.", comment: "")
            case -25293: 
                return NSLocalizedString("Keychain authentication failed.", comment: "")
            default:
                return NSLocalizedString("Keychain security error.", comment: "")
            }
        }
        return error.localizedDescription
    }

    private func processError(_ error: NSError, ignoreTitle: Bool = false, getMoreErrors: (_ error: NSError)->String) -> String{
        let serializedError = "\(error)"
        if unique && errors.contains(serializedError) {
            return ""
        }
        errors.insert(serializedError)    
        var title = ""
        var desc = ""
        switch (info){
            case .localizedDescription:
                title = !ignoreTitle ? (error.localizedTitle.map{$0+"\n"} ?? "") : ""
                desc = userFriendlyDescription(for: error)
            case .fullError:
                desc = serializedError
        }
        var moreErrors = getMoreErrors(error)
        moreErrors = moreErrors == "" ? "" : "\n" + moreErrors
        return title + desc + moreErrors
    }

    func getDescription(error: NSError) -> String{
        errors = []  
        return getDescriptionText(error: error)
    }
    func getDescriptionText(error: NSError,_ depth: Int = 0) -> String{
        let recurseErrors = { error in
            self.getDescriptionText(error: error, depth+1)
        }
        var description = ""
        let processMoreErrors = recur ? recurseErrors : {_ in ""}
        let underlyingErrors = error.underlyingErrors
        if let wrappedError = (error as? ALTWrappedError)?.wrappedError {
            description += getDescriptionText(error: wrappedError, depth + 1)
        } else if !underlyingErrors.isEmpty {
            description += underlyingErrors.map{ error in
                let error = error as NSError
                return processError(error, getMoreErrors: processMoreErrors)
            }.joined(separator: "\n")
        } else if let underlyingError = error.underlyingError as? NSError {
            let error = underlyingError as NSError
            description += processError(error, getMoreErrors: processMoreErrors)
        } else {
            let isBaseError = (depth == 0)
            description += processError(error, ignoreTitle: isBaseError, getMoreErrors: processMoreErrors)
        }
        return description
    }
}
