class DeployCheckException(Exception):
    def __init__(self, msg):
        super(DeployCheckException, self).__init__(msg)
        self.msg = msg
