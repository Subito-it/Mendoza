import Bariloche
import Foundation
import MendozaCore

setbuf(__stdoutp, nil)

let parser = Bariloche(command: RootCommand())
let result = parser.parse()
