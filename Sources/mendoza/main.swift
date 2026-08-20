import Bariloche
import Foundation

setbuf(__stdoutp, nil)

// Plugins are fed their input over a pipe. If one exits without reading it, writing to the
// closed pipe would otherwise raise SIGPIPE and take Mendoza down with it.
signal(SIGPIPE, SIG_IGN)

let parser = Bariloche(command: RootCommand())
let result = parser.parse()
