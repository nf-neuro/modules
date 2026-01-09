include { IO_READBIDS   } from '../../../modules/nf-neuro/io/readbids/main.nf'

workflow IO_BIDS {

    take:
    bids_folder         // channel: [ path(bids_folder) ]
    fs_folder           // channel: [ path(fs_folder) ]
    bidsignore          // channel: [ path(bids_ignore) ]

    main:

    ch_versions = channel.empty()

    // ** Sanity check to ensure channels are single-item ** //
    bids_folder.collect().map { folders ->
        if (folders.size() > 1) {
            error "ERROR: You must supply only a single BIDS folder."
        }
    }

    // ** Fetching the BIDS data as a json file ** //
    IO_READBIDS (
        bids_folder,
        fs_folder.ifEmpty( [] ),
        bidsignore.ifEmpty( [] )
    )
    ch_versions = ch_versions.mix(IO_READBIDS.out.versions)

    // ** Converting the json file into channels. ** //
    ch_files = IO_READBIDS.out.bidsstructure
        .flatMap{ layout ->
            def json = new groovy.json.JsonSlurper().parseText(layout.getText())
            return json.collect { item ->
                // ** Collecting the subject's ID ** //
                def sid = "sub-" + item.subject

                // ** Collecting the session's ID if present ** //
                def ses = item.session ? "ses-" + item.session : ""

                // ** Collecting the run's ID if present ** //
                def run = item.run ? "run-" + item.run : ""

                // ** Collecting TotalReadoutTime, PhaseEncodingDirection ** //
                def dwi_tr = item.TotalReadoutTime ?: ""
                def dwi_phase = item.DWIPhaseEncodingDirection ?: ""
                def dwi_revphase = item.rev_DWIPhaseEncodingDirection ?: ""

                // ** Validating there is not missing data ** //
                item.each { _key, value ->
                    if (value == "todo") {
                        error   "ERROR ~ $sid contains missing files, please" +
                                "check the BIDS layout. You can validate your" +
                                "structure using the bids-validator tool:" +
                                "https://bids-standard.github.io/bids-validator/" +
                                "or the docker version: " +
                                "https://hub.docker.com/r/bids/validator"
                    }
                }

                // ** Collecting the files ** //
                return [
                    [id: sid, session: ses, run: run, dwi_tr: dwi_tr,
                    dwi_phase: dwi_phase, dwi_revphase: dwi_revphase],
                    item.t1 ? file(item.t1) : [],
                    item.wmparc ? file(item.wmparc) : [],
                    item.aparc_aseg ? file(item.aparc_aseg) : [],
                    item.dwi ? file(item.dwi) : [],
                    item.bval ? file(item.bval) : [],
                    item.bvec ? file(item.bvec) : [],
                    item.rev_dwi ? file(item.rev_dwi) : [],
                    item.rev_bval ? file(item.rev_bval) : [],
                    item.rev_bvec ? file(item.rev_bvec) : [],
                    item.rev_topup ? file(item.rev_topup) : [],
                ]
            }
        }
        .multiMap{ meta, t1, wmparc, aparc_aseg, dwi, bval, bvec, rev_dwi, rev_bval, rev_bvec, rev_b0 ->
            t1: [meta, t1]
            wmparc: [meta, wmparc]
            aparc_aseg: [meta, aparc_aseg]
            dwi_bval_bvec: [meta, dwi, bval, bvec]
            rev_dwi_bval_bvec: [meta, rev_dwi, rev_bval, rev_bvec]
            rev_b0: [meta, rev_b0]
        }

    emit:
    ch_t1                   = ch_files.t1                   // channel: [ [meta], file(t1) ]
    ch_wmparc               = ch_files.wmparc               // channel: [ [meta], file(wmparc) ]
    ch_aparc_aseg           = ch_files.aparc_aseg           // channel: [ [meta], file(aparc_aseg) ]
    ch_dwi_bval_bvec        = ch_files.dwi_bval_bvec        // channel: [ [meta], file(dwi), file(bval), file(bvec) ]
    ch_rev_dwi_bval_bvec    = ch_files.rev_dwi_bval_bvec    // channel: [ [meta], file(rev_dwi), file(rev_bval), file(rev_bvec) ]
    ch_rev_b0               = ch_files.rev_b0               // channel: [ [meta], file(fieldmap) ]

    versions = ch_versions                     // channel: [ versions.yml ]
}

