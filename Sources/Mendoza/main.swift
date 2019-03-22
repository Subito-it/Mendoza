import Foundation
import Bariloche

setbuf(__stdoutp, nil);

let parser = Bariloche(command: RootCommand())
let result = parser.parse()
