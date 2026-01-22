include { BUNDLE_BUNDLEPARC } from '../../../modules/nf-neuro/bundle/bundleparc/main.nf'

def compute_file_hash(file_path) {
    def file = new File(file_path)
    if (!file.exists()) {
        error "File not found: $file_path"
    }

    def digest = java.security.MessageDigest.getInstance("MD5")
    def fileBytes = java.nio.file.Files.readAllBytes(java.nio.file.Paths.get(file_path))
    def hashBytes = digest.digest(fileBytes)
    return hashBytes.collect { String.format("%02x", it) }.join('')
}

def fetch_bundleparc_checkpoint(dest) {
    def checkpoint_url = "https://zenodo.org/records/15579498/files/123_4_5_bundleparc.ckpt"
    def checkpoint_md5 = ""

    if (file("$workflow.workDir/weights/123_4_5_bundleparc.ckpt").exists()) {
        def existing_md5 = compute_file_hash("$workflow.workDir/weights/123_4_5_bundleparc.ckpt")
        if (existing_md5 == checkpoint_md5) {
            println "BundleParc checkpoint already exists and is valid."
            return "$workflow.workDir/weights/123_4_5_bundleparc.ckpt"
        } else {
            println "Existing BundleParc checkpoint is invalid. Re-downloading..."
            new File("$workflow.workDir/weights/123_4_5_bundleparc.ckpt").delete()
        }
    }

    def path = java.nio.file.Paths.get("$dest/weights/")
    if (!java.nio.file.Files.exists(path)) {
        java.nio.file.Files.createDirectories(path)
    }

    println("Downloading BundleParc checkpoint from $checkpoint_url...")
    def weights = new File("$dest/weights/123_4_5_bundleparc.ckpt").withOutputStream { out ->
        new URL(checkpoint_url).withInputStream { from -> out << from; }
    }
    println("Download completed.")

    return weights
}

workflow BUNDLEPARC {

    take:
        ch_fodf // channel: [ val(meta), [ fodf ] ]

    main:
        ch_versions = Channel.empty()
        ch_multiqc_files = Channel.empty()

        if ( params.checkpoint ) {
            weights = Channel.fromPath("$params.checkpoint", checkIfExists: true, relative: true)
        }
        else {
            if ( !file("$workflow.workDir/weights/123_4_5_bundleparc.ckpt").exists() ) {
                fetch_bundleparc_checkpoint("${workflow.workDir}/")
            }
            weights = Channel.fromPath("$workflow.workDir/weights/123_4_5_bundleparc.ckpt", checkIfExists: true)
        }

        ch_fodf =  ch_fodf.combine(weights)

        BUNDLE_BUNDLEPARC(ch_fodf)
        ch_versions = ch_versions.mix(BUNDLE_BUNDLEPARC.out.versions)

    emit:
        bundles     = BUNDLE_BUNDLEPARC.out.labels // channel: [ val(meta), [ bundles ] ]
        mqc         = ch_multiqc_files             // channel: [ multiqc files ]
        versions    = ch_versions                  // channel: [ versions.yml ]
}
